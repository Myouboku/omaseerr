# AGENTS.md

OmaSeerr is an Omarchy shell plugin (QML, Quickshell) that shows Seerr media
requests in the bar and lets the user approve, decline and delete them. Read
`README.md` for what it does; this file is what an agent needs to work on it
safely.

## Never use the real Seerr instance

The checkout is usually symlinked into `~/.config/omarchy/plugins/myouboku.omaseerr`,
so the running shell uses this code, configured **against the user's real Seerr
instance** (real requests, real users). Do not use that instance for anything:
not to look at the panel, not to take screenshots, not to read requests, not
through IPC. Always work against the mock:

```bash
dev/use-mock.sh on      # fake Seerr on http://127.0.0.1:5056 with one pending request
dev/use-mock.sh status  # "on the mock" before doing anything with the live plugin
dev/use-mock.sh off     # restores the saved URL, stops the mock, drops its key
```

- Run `on` before any `omarchy-shell myouboku.omaseerr …` call, panel
  screenshot or synthetic key (`wtype`), and check `status` says "on the mock".
- After `omarchy restart shell`, check `status` again before going on.
- Run `off` before ending the task.
- The real API key stays in the keyring (keys are bound to the URL's origin),
  so it is never sent to the mock; never read, print or move it.
- Synthetic keys go to whatever window has focus: check the panel is open
  first, or they land in another app.

## Layout

| File | Role |
|------|------|
| `manifest.json` | plugin id, version, settings defaults and schema |
| `Service.qml` | single instance: keyring, HTTP (curl), polling, notifications, actions, IPC |
| `Panel.qml` | bar icon and panel (one per monitor): list, detail, approve form, settings |
| `model/Seerr.js` | pure logic: URLs, payload validation, statuses, filters, settings, approval form |
| `i18n/en.json`, `i18n/fr.json` | translations, same keys in both |
| `tests/run.js` | `node` tests for `model/Seerr.js` |
| `dev/` | mock Seerr, `use-mock.sh`, Docker stack with a real Seerr |

The Omarchy UI kit the panel builds on lives in `/usr/share/omarchy/shell/Ui/`
(`Dropdown.qml`, `BarIconButton.qml`, …). Read it when a kit component behaves
unexpectedly.

## Checking a change

```bash
node tests/run.js                 # must stay green
omarchy restart shell             # the only reliable way to reload QML
journalctl --user --since "-15s" | grep -iE "Panel.qml|Service.qml|omaseerr"   # QML errors
```

The scanner warning "Module path … is outside of the config folder" is normal.

## Conventions

- **Text from Seerr is never rich text.** Use the `PlainText` component (or
  `textFormat: Text.PlainText`) for anything that can contain Seerr data;
  `dev/mock-seerr.js --hostile` checks it.
- **Strings** go through `root.t("key")` / `root.tn("key", n)`. Add every key
  to both `i18n/en.json` and `i18n/fr.json`. Keyboard hints (`list.keys`,
  `detail.keys`, …) use the format `key label · key label`; the `KeyHints`
  component parses it, so keys must not contain spaces.
- **A setting** lives in five places, keep them in sync: `manifest.json`
  (`defaults` and `schema`), `DEFAULTS` and `normalizeSettings` in
  `model/Seerr.js`, the settings page in `Panel.qml`, and the table in
  `README.md`.
- **Pure logic goes in `model/Seerr.js`** with a test in `tests/run.js`; QML
  stays thin.

## QML pitfalls already hit

- The kit's `Dropdown` assigns its own `value` when an option is picked, which
  breaks a `value:` binding. Use `SyncedDropdown` and bind `current:` instead.
- `BarIconButton` only sizes an `iconComponent` item that has no size of its
  own. For a single glyph, set the button's `text` and `foreground` instead, so
  the kit centres it like the other bar icons.
- Content placed after the rows inside a `Flickable` scrolls away with them;
  anything that must stay visible (the shortcut hints) is anchored outside it.

## Git

- Commit messages in English, imperative subject, a short body saying why.
- Commit, push or tag only when the user asks. Work happens on `v1`; `master`
  is the main branch.
