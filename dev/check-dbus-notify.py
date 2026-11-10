#!/usr/bin/env python3
# Checks service/dbus-notify.pl against a stand-in notification daemon on a
# private session bus: what it sends must arrive as sent, and nothing from the
# notification may show on its command line. Needs python-gobject (dev only).
#
#   dbus-run-session -- python3 -I dev/check-dbus-notify.py

import json, os, subprocess, sys, threading
from gi.repository import Gio, GLib

HERE = os.path.dirname(os.path.abspath(__file__))
HELPER = os.path.join(HERE, "..", "service", "dbus-notify.pl")

XML = """<node><interface name="org.freedesktop.Notifications">
<method name="Notify"><arg type="s"/><arg type="u"/><arg type="s"/><arg type="s"/><arg type="s"/>
<arg type="as"/><arg type="a{sv}"/><arg type="i"/><arg type="u" direction="out"/></method>
</interface></node>"""

received = []
loop = GLib.MainLoop()
bus = Gio.bus_get_sync(Gio.BusType.SESSION)


def on_call(conn, sender, path, iface, method, params, invocation):
    received.append(params.unpack())
    invocation.return_value(GLib.Variant("(u)", (len(received),)))


bus.register_object("/org/freedesktop/Notifications", Gio.DBusNodeInfo.new_for_xml(XML).interfaces[0], on_call, None, None)
Gio.bus_own_name_on_connection(bus, "org.freedesktop.Notifications", Gio.BusNameOwnerFlags.NONE, None, None)

failures = []


def check(name, cond):
    print(("ok   " if cond else "FAIL ") + name)
    if not cond:
        failures.append(name)


actions = json.dumps([{"label": "Details", "argv": ["omarchy-shell", "x", "show", "12@https://seerr.example"]}])
cases = [
    {"app": "Seerr", "summary": "--New request: Amélie 🎬", "body": "by <b>Bob</b> · Series · Seasons 1–3",
     "urgency": 2, "hints": {"omarchy-glyph": "\U000f0fce", "image-path": "/tmp/p.jpg", "omarchy-actions": actions}},
    {"app": "Seerr", "summary": "x" * 5000, "body": "", "urgency": 0, "hints": {}},
    {"app": "Seerr", "summary": "nul\u0000cut", "body": "é", "hints": {"bad": ["not", "a", "string"]}},
]


def run():
    for c in cases:
        p = subprocess.Popen(["perl", HELPER], stdin=subprocess.PIPE, stderr=subprocess.PIPE)
        cmdline = open(f"/proc/{p.pid}/cmdline", "rb").read()
        p.stdin.write(json.dumps(c).encode())
        p.stdin.close()
        err = p.stderr.read().decode()
        check(f"exit 0 ({err.strip() or 'no error'})", p.wait() == 0)
        check("command line carries no text", b"Seerr" not in cmdline and b"request" not in cmdline)
    GLib.idle_add(loop.quit)


threading.Thread(target=run, daemon=True).start()
GLib.timeout_add_seconds(20, loop.quit)
loop.run()

check("three notifications received", len(received) == 3)
if len(received) == 3:
    app, rid, icon, summary, body, acts, hints, timeout = received[0]
    check("first: app, summary, body", (app, summary, body) == ("Seerr", cases[0]["summary"], cases[0]["body"]))
    check("first: id, icon, actions, timeout", (rid, icon, acts, timeout) == (0, "", [], -1))
    check("first: hints", hints == {"urgency": 2, "omarchy-glyph": "\U000f0fce", "image-path": "/tmp/p.jpg", "omarchy-actions": actions})
    check("long summary intact", received[1][3] == "x" * 5000 and received[1][6] == {"urgency": 0})
    check("NUL dropped, bad hint skipped",
          received[2][3] == "nulcut" and received[2][4] == "é" and received[2][6] == {"urgency": 1})

sys.exit(1 if failures else 0)
