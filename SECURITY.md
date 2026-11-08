# Security

OmaSeerr holds a Seerr API key, which can approve, decline and delete requests on your server. Reports about anything that could expose that key or act on Seerr without you asking are welcome.

## Reporting a vulnerability

Please report it privately through GitHub: **Security › Report a vulnerability** on this repository ([direct link](https://github.com/Myouboku/omaseerr/security/advisories/new)). Do not open a public issue for it.

Include what you did, what happened, and the version (`manifest.json`) or commit you tested. You will get an answer as soon as possible, and a fix is released before the details are made public.

## Scope

In scope:

- the API key leaving the keyring for anything other than the Seerr origin it was saved for (redirects, URL changes, logs, command lines, files);
- data from Seerr being interpreted instead of displayed: markup in the panel or notifications, options or commands in notification actions, paths outside the poster cache;
- notification buttons or IPC calls acting on a request they were not about.

Out of scope: weaknesses of Seerr itself (report them to [Seerr](https://github.com/seerr-team/seerr/security)), the API key travelling in clear over plain HTTP to a server outside your network (the panel warns about it), and other programs running as your user, which can already read your keyring.
