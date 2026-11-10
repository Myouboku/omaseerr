#!/usr/bin/perl
# Sends one desktop notification on the session bus
# (org.freedesktop.Notifications.Notify), read as JSON on stdin:
#
#   { "app": "Seerr", "summary": "…", "body": "…", "urgency": 0|1|2,
#     "timeout": -1, "hints": { "omarchy-glyph": "…", … } }
#
# Hints other than urgency are strings. Prints nothing; exits 0 once the
# daemon has answered, 1 otherwise (the reason on stderr).
#
# TEMPORARY. This exists only because omarchy-notification-send takes the
# headline and body as arguments and passes them on to busctl as arguments
# too, so the titles and requesters in our notifications were readable by any
# local account in /proc/<pid>/cmdline. Here they travel on stdin and on the
# bus socket, and the command line is only `perl …/dbus-notify.pl`. Once
# Omarchy can send a notification without putting its text on a command line
# (stdin, or a shell API for plugins), drop this file and go back to it: see
# "Temporary" in AGENTS.md.
#
# Only core Perl modules: perl is a dependency of the omarchy package.

use strict;
use warnings;
use IO::Socket::UNIX;
use JSON::PP;

$SIG{ALRM} = sub { fail("no answer from the session bus") };
alarm 10;

sub fail { print STDERR "dbus-notify: $_[0]\n"; exit 1 }

my $input = do { local $/; <STDIN> } // '';
my $n = eval { JSON::PP->new->utf8->decode($input) };
fail("input is not a JSON object") unless ref $n eq 'HASH';

# ------------------------------------------------------------- connecting

sub bus_path {
  for my $address (split /;/, $ENV{DBUS_SESSION_BUS_ADDRESS} // '') {
    next unless $address =~ /^unix:(.*)$/;
    my %kv = map { my ($k, $v) = split /=/, $_, 2; ($k, $v // '') } split /,/, $1;
    for (values %kv) { s/%([0-9A-Fa-f]{2})/chr hex $1/ge }
    return $kv{path} if defined $kv{path};
    return "\0$kv{abstract}" if defined $kv{abstract};
  }
  return ($ENV{XDG_RUNTIME_DIR} // "/run/user/$<") . "/bus";
}

my $sock = IO::Socket::UNIX->new(Type => SOCK_STREAM(), Peer => bus_path())
  or fail("cannot reach the session bus: $!");
binmode $sock;
$sock->autoflush(1);

# EXTERNAL authentication: the bus checks our uid on the socket itself.
print $sock "\0AUTH EXTERNAL " . unpack('H*', "$<") . "\r\n";
my $line = do { local $/ = "\r\n"; <$sock> } // '';
fail("the session bus refused us") unless $line =~ /^OK /;
print $sock "BEGIN\r\n";

# ------------------------------------------------------------- marshalling
# Little-endian, each value aligned on its size from the start of the
# message (the body starts on 8, so a body built from 0 aligns the same).

sub align { my ($b, $n) = @_; $$b .= "\0" x ((-length $$b) % $n) }

# Text for the bus: valid UTF-8, no NUL.
sub bytes {
  my $s = defined $_[0] ? "$_[0]" : '';
  $s =~ s/\0//g;
  $s =~ s/[\x{D800}-\x{DFFF}]/\x{FFFD}/g;
  utf8::encode($s);
  return $s;
}

sub put {
  my ($b, $sig, $v) = @_;
  if ($sig eq 'y') { $$b .= pack 'C', $v }
  elsif ($sig eq 'u') { align($b, 4); $$b .= pack 'V', $v }
  elsif ($sig eq 'i') { align($b, 4); $$b .= pack 'l<', $v }
  elsif ($sig eq 's' || $sig eq 'o') { my $s = bytes($v); align($b, 4); $$b .= pack('V', length $s) . $s . "\0" }
  elsif ($sig eq 'g') { $$b .= pack('C', length $v) . $v . "\0" }
  else { fail("cannot send type $sig") }
}

sub put_variant { my ($b, $sig, $v) = @_; put($b, 'g', $sig); put($b, $sig, $v) }

# An array whose elements align on $elem_align; $each appends one element.
sub put_array {
  my ($b, $elem_align, $items, $each) = @_;
  align($b, 4);
  my $at = length $$b;
  $$b .= "\0" x 4;
  align($b, $elem_align);
  my $start = length $$b;
  $each->($_) for @$items;
  substr($$b, $at, 4) = pack 'V', length($$b) - $start;
}

my $serial = 0;

sub message {
  my (%m) = @_;
  my $body = $m{body} // '';
  my $msg = pack 'a C C C V V', 'l', 1, 0, 1, length $body, ++$serial;
  my @fields = ([1, 'o', $m{path}], [2, 's', $m{interface}], [3, 's', $m{member}], [6, 's', $m{destination}]);
  push @fields, [8, 'g', $m{signature}] if $m{signature};
  put_array(\$msg, 8, \@fields, sub { align(\$msg, 8); put(\$msg, 'y', $_[0][0]); put_variant(\$msg, $_[0][1], $_[0][2]) });
  align(\$msg, 8);
  print $sock $msg . $body;
  return $serial;
}

# ------------------------------------------------------------- reading

sub read_n {
  my ($want) = @_;
  my $buf = '';
  while (length $buf < $want) {
    my $got = read($sock, $buf, $want - length $buf, length $buf);
    fail("the session bus hung up") unless $got;
  }
  return $buf;
}

# One message: its type, the serial it answers, and its error name.
sub read_message {
  my $fixed = read_n(16);
  my $u = substr($fixed, 0, 1) eq 'B' ? 'N' : 'V';
  my $type = ord substr($fixed, 1, 1);
  my $body_len = unpack $u, substr($fixed, 4, 4);
  my $fields_len = unpack $u, substr($fixed, 12, 4);
  fail("message too large") if $body_len > 1 << 24 || $fields_len > 1 << 24;
  my $header_end = 16 + $fields_len;
  my $msg = $fixed . read_n($header_end + ((-$header_end) % 8) - 16 + $body_len);
  my %info = (type => $type, reply => 0, error => '');
  my $p = 16;
  while ($p < $header_end) {
    $p += (-$p) % 8;
    my $code = ord substr($msg, $p++, 1);
    my $sig_len = ord substr($msg, $p++, 1);
    my $sig = substr($msg, $p, $sig_len);
    $p += $sig_len + 1;
    if ($sig eq 'u') { $p += (-$p) % 4; $info{reply} = unpack $u, substr($msg, $p, 4) if $code == 5; $p += 4 }
    elsif ($sig eq 's' || $sig eq 'o') {
      $p += (-$p) % 4;
      my $len = unpack $u, substr($msg, $p, 4);
      $info{error} = substr($msg, $p + 4, $len) if $code == 4;
      $p += 4 + $len + 1;
    }
    elsif ($sig eq 'g') { $p += 1 + ord(substr($msg, $p, 1)) + 1 }
    else { last }
  }
  return \%info;
}

# ------------------------------------------------------------- sending

message(path => '/org/freedesktop/DBus', interface => 'org.freedesktop.DBus',
  member => 'Hello', destination => 'org.freedesktop.DBus');

my $urgency = $n->{urgency} // 1;
$urgency = 1 unless $urgency =~ /^[012]$/;
my $hints = ref $n->{hints} eq 'HASH' ? $n->{hints} : {};
my @hints = (['urgency', 'y', $urgency], map { [$_, 's', $hints->{$_}] } sort grep { defined $hints->{$_} && !ref $hints->{$_} } keys %$hints);
my $timeout = defined $n->{timeout} && $n->{timeout} =~ /^-?\d+$/ ? $n->{timeout} : -1;

my $body = '';
put(\$body, 's', $n->{app});
put(\$body, 'u', 0);
put(\$body, 's', '');
put(\$body, 's', $n->{summary});
put(\$body, 's', $n->{body});
put_array(\$body, 4, [], sub {});
put_array(\$body, 8, \@hints, sub { align(\$body, 8); put(\$body, 's', $_[0][0]); put_variant(\$body, $_[0][1], $_[0][2]) });
put(\$body, 'i', $timeout);

my $notify = message(path => '/org/freedesktop/Notifications', interface => 'org.freedesktop.Notifications',
  member => 'Notify', destination => 'org.freedesktop.Notifications', signature => 'susssasa{sv}i', body => $body);

while (1) {
  my $m = read_message();
  next unless $m->{reply} == $notify;
  exit 0 if $m->{type} == 2;
  fail("the notification daemon answered " . ($m->{error} || "an error")) if $m->{type} == 3;
}
