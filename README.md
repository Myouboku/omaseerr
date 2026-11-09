# OmaSeerr

[Seerr](https://github.com/seerr-team/seerr) media requests in the [Omarchy](https://omarchy.org) bar.

![OmaSeerr panel](preview.png)

- **Bar icon** in the accent color while requests are pending, a red warning sign when Seerr is unreachable; the tooltip gives the count. Right-click refreshes, middle-click opens Seerr.
- **Panel**: requests with posters, filter by status and media type, sort by request or update date, search by title or user.
- **Details**: poster, synopsis, genres, requested seasons, who asked and when, who handled it.
- **Approve with options**: choose the Radarr/Sonarr server, quality profile, root folder, language profile, tags and seasons, like Seerr's own approval dialog (anime defaults included). **Shift+click** (or `A`) approves straight away with Seerr's defaults.
- **Decline, retry, delete** (with confirmation).
- **Notifications** for new requests with **Details / Approve / Decline** buttons. Approve from a notification is a quick approval. Several new requests at once can be grouped, and optional notifications when a request becomes available or fails.
- **Everything is configurable** from the panel's settings (gear icon) or `shell.json`.
- English and French; follows the language chosen in Omarchy.

## Requirements

- [Omarchy](https://omarchy.org) with its shell, which provides the bar, the panel, notifications (`omarchy-notification-send`) and IPC (`omarchy-shell`).
- `secret-tool` (package `libsecret`) and a Secret Service provider such as gnome-keyring or KeePassXC, to keep the API key.
- `curl` and `bash`, for API calls and poster downloads.
- A [Seerr](https://github.com/seerr-team/seerr) instance and its API key. Network access to `image.tmdb.org` for posters, unless both poster settings are off.

Omarchy ships all of these except Seerr; nothing else is installed.

## Install

```bash
omarchy plugin add https://github.com/myouboku/omaseerr --enable
```

Then click the icon: the panel opens on its settings. Enter the Seerr URL (`http://` or `https://`) and the API key from **Seerr › Settings › General**.

### The API key

The key is kept in your keyring through the Secret Service (`secret-tool`, which gnome-keyring or KeePassXC provide), under `service=myouboku.omaseerr account=api-key origin=<scheme://host[:port]>`. It never goes into `shell.json`, a file, or a command line.

The key is bound to the origin of the Seerr URL it was saved for, and is only ever sent there. Pointing the plugin at another scheme, host or port (a typo, a copied `shell.json`, `omarchy-shell … set url`) does not carry the key along: the panel asks for the key of the new address. The path and the scheme's default port do not count, so `https://seerr.example.com/seerr` uses the key of `https://seerr.example.com`.

To manage it by hand:

```bash
secret-tool store --label="OmaSeerr (Seerr API key)" service myouboku.omaseerr account api-key origin https://seerr.example.com   # paste, then Ctrl+D
omarchy-shell myouboku.omaseerr reloadKey
secret-tool clear service myouboku.omaseerr account api-key   # every stored key, all origins
```

A key that cannot manage requests (neither admin nor *Manage Requests*) still lists them, but the approve and decline actions are hidden.

**HTTP or HTTPS** both work. The panel warns when plain HTTP points outside your local network, since the key then travels unencrypted. For HTTPS, the certificate must be valid (self-signed certificates are refused).

**Redirects are not followed.** Requests go through `curl` without `-L`, so a redirect (an HTTP to HTTPS upgrade, an authentication portal in front of Seerr, a moved instance) never carries the key to another address: the panel shows where Seerr points instead, and you can set that as the URL if it is the right one. The key reaches `curl` on stdin, not on its command line.

### Remove

```bash
omarchy plugin remove myouboku.omaseerr
secret-tool clear service myouboku.omaseerr account api-key   # the stored API key(s)
rm -rf ~/.local/state/omaseerr ~/.cache/omaseerr              # seen request ids, cached posters
```

## Keyboard

| Key | List | Details |
|-----|------|---------|
| `↑` `↓` / `j` `k` | move | |
| `Enter` | details | approve… |
| `a` | approve with options | approve with options |
| `A` / `Shift+Enter` | quick approve | quick approve |
| `d` | decline | decline |
| `x` / `Delete` | delete | delete |
| `R` | retry a failed request | retry |
| `o` | open in Seerr | open in Seerr |
| `f` / `F` | next / previous status filter | |
| `t` | next media type | |
| `S` / `i` | sort field / direction | |
| `/` | search (`Enter` or `↓` back to the list) | |
| `r` | refresh | |
| `s` | settings | |
| `Esc` | close (clears the search first) | back |

## Settings

All of them are in the panel (gear icon). They are stored in the widget's entry in `~/.config/omarchy/shell.json` and can also be set with `omarchy bar set myouboku.omaseerr <key> <value>` or `omarchy-shell myouboku.omaseerr set <key> <value>`.

| Key | Default | |
|-----|---------|---|
| `url` | | Seerr address, `http://` or `https://` |
| `refreshIntervalSec` | `60` | how often to check for new requests (15–3600) |
| `notifyNewRequests` | `true` | notify new requests |
| `notifyStatusChanges` | `false` | notify when a request becomes available or fails |
| `notifyOnStartup` | `false` | announce the requests already pending at the first connection |
| `notifyUrgency` | `normal` | `low`, `normal`, `critical` |
| `notifyPoster` | `true` | poster in notifications (downloaded from TMDB, cached in `~/.cache/omaseerr`) |
| `notifyGroupThreshold` | `3` | one grouped notification from this many new requests (`1` never groups) |
| `defaultFilter` | `pending` | `pending`, `approved`, `processing`, `available`, `failed`, `declined`, `all` |
| `defaultMediaType` | `all` | `all`, `movie`, `tv` |
| `defaultSort` | `added` | `added`, `modified` |
| `defaultSortDirection` | `desc` | `desc`, `asc` |
| `pageSize` | `20` | requests per page (5–100) |
| `showPosters` | `true` | posters in the panel (loaded from image.tmdb.org) |
| `confirmDecline` | `true` | ask before declining |

## IPC

```bash
omarchy-shell myouboku.omaseerr status          # connected pending=3 total=42
omarchy-shell myouboku.omaseerr pending         # 3
omarchy-shell myouboku.omaseerr open | toggle | refresh
omarchy-shell myouboku.omaseerr show <id>       # open the panel on a request
omarchy-shell myouboku.omaseerr approve <id>    # quick approve
omarchy-shell myouboku.omaseerr decline <id>
omarchy-shell myouboku.omaseerr get|set <key> [value]
```

`approve` and `decline` (and the notification buttons, which use them) first read the request and only act on it while it is still pending, so an old notification cannot overturn a decision taken since. Notifications also name the server they came from (`<id>@<origin>`): once the URL points to another Seerr, their buttons do nothing.

A Hyprland binding, for example in `~/.config/hypr/bindings.lua`, can open the panel with `omarchy-shell myouboku.omaseerr toggle`.

## Network and privacy

The plugin talks to your Seerr instance only. It checks it every `refreshIntervalSec` seconds while connected (the count, the 50 newest pending requests, and the 50 latest updates when status notifications are on). Posters come from `image.tmdb.org` unless both poster settings are off. Answers are size-limited and validated, and text from Seerr is always displayed as plain text. Seen request ids are kept in `~/.local/state/omaseerr/state.json` so a restart does not announce them again.

## Development

```bash
node tests/run.js                       # model tests
node dev/mock-seerr.js                  # fake Seerr on http://127.0.0.1:5055, key devkey1234567890
node dev/mock-seerr.js --hostile        # plus markup in a title and a user name, and a bad poster path
curl -X POST 'http://127.0.0.1:5055/__mock/new?type=tv'   # a new pending request
docker compose -f dev/compose.yaml up -d                  # a real Seerr, Jellyfin, Radarr, Sonarr
dev/use-mock.sh on [--hostile]          # point the running plugin at a fake Seerr on :5056
dev/use-mock.sh off                     # back to your own URL; your key never leaves for the mock
```

Link the checkout as a plugin with `ln -s "$PWD" ~/.config/omarchy/plugins/myouboku.omaseerr`, then `omarchy plugin enable myouboku.omaseerr --section right`. After changing a QML file, `omarchy restart shell` is the reliable way to reload it: the shell keeps already-compiled QML types in memory.

| File | Role |
|------|------|
| `manifest.json` | plugin id, kinds (`service` + `bar-widget`), settings schema |
| `Service.qml` | the single instance: keyring, HTTP, polling, notifications, actions, IPC |
| `Panel.qml` | bar icon and panel (one per monitor), all views |
| `model/Seerr.js` | pure logic: URLs, payload validation, statuses, filters, approval form |
| `i18n/*.json` | translations |
| `tests/` | `node` tests for the model |
| `dev/` | fake Seerr and a Docker stack with a real one |

## License

[MIT](LICENSE). OmaSeerr is not affiliated with Seerr, Omarchy or TMDB. Posters are loaded from TMDB and belong to their owners.
