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

| Path | Role |
|------|------|
| `manifest.json` | plugin id, version, settings defaults and schema |
| `Service.qml` | the one instance per shell: settings, translations, IPC; creates the parts in `service/` and forwards what panels use |
| `service/` | the service's parts: `Keyring`, `Http` (curl), `Connection`, `Poller`, `RequestStore`, `Actions`, `ArrServers`, `Notifier`, `StateFile` |
| `Panel.qml` | bar icon and panel (one per monitor); wires the parts below and is the `ctx` they get |
| `panel/` | one panel's state: `PanelState` (page, cursor, toast, actions), `ApprovalForm`, `Keyboard` |
| `pages/` | the panel's pages: `ListPage`, `DetailPage`, `ApprovePage`, `SettingsPage` |
| `ui/` | display-only components (`RequestRow`, `KeyHints`, `PlainText`, …) and `Glyphs.js` |
| `model/` | pure logic, no Qt, one `.pragma library` file per topic: |
| `model/values.js` | reading untrusted values: bounded strings, ints, ids, dates, JSON |
| `model/api.js` | base URL and key origin, API paths, web and poster links, normalising API answers |
| `model/curl.js` | curl's argv and stdin config, its output turned into an API answer |
| `model/requests.js` | statuses and colours, filters and sorts, merging pages, seasons |
| `model/notify.js` | new requests, status changes, the state file, markup-proof text |
| `model/settings.js` | plugin id, settings defaults and validation, the bar entry |
| `model/form.js` | the approval form: servers, initial choices, problems, PUT body |
| `model/time.js` | relative times, date patterns |
| `model/keymap.js` | which panel action a key stands for |
| `model/cursor.js` | the list cursor, stepping between details, scrolling into view |
| `model/hints.js` | shortcut hints: parsing `key label · …`, balanced line layout |
| `i18n/en.json`, `i18n/fr.json` | translations, same keys in both |
| `tests/` | `<module>.test.js` per model file, `run.js` runs them, `harness.js` loads model files as QML does |
| `dev/` | mock Seerr, `use-mock.sh`, Docker stack with a real Seerr |

The Omarchy UI kit the panel builds on lives in `/usr/share/omarchy/shell/Ui/`
(`Dropdown.qml`, `BarIconButton.qml`, …). Read it when a kit component behaves
unexpectedly.

## Checking a change

```bash
node tests/run.js                 # must stay green
node tests/run.js keymap cursor   # only those modules' tests
omarchy restart shell             # the only reliable way to reload QML
journalctl --user --since "-15s" | grep -iE "qml|omaseerr" | grep -v "outside of the config"   # QML errors
```

The scanner warning "Module path … is outside of the config folder" is
normal, and so is "Cannot set activeFocusOnTab to false…". Pages are built
when the panel first opens, so open it and visit every page before reading
the journal.

## Conventions

- **Text from Seerr is never rich text.** Use the `PlainText` component (or
  `textFormat: Text.PlainText`) for anything that can contain Seerr data;
  `dev/mock-seerr.js --hostile` checks it.
- **Strings** go through `ctx.t("key")` / `ctx.tn("key", n)` in pages and
  `panel/`, `svc.t` / `svc.tn` in `service/`. Add every key to both
  `i18n/en.json` and `i18n/fr.json`. Keyboard hints (`list.keys`,
  `detail.keys`, …) use the format `key label · key label`
  (`model/hints.js` parses it), so keys must not contain spaces;
  `tests/hints.test.js` checks every key cap against its list of known
  keys: add a new one there.
- **A setting** lives in five places, keep them in sync: `manifest.json`
  (`defaults` and `schema`), `DEFAULTS` and `normalizeSettings` in
  `model/settings.js`, `pages/SettingsPage.qml`, and the table in
  `README.md`.
- **Keyboard first.** Every interactive control is reachable with Tab and
  shows its focus (`ActionButton` and `Chip` handle it; kit controls do it
  themselves; `IconButton` too, except a row's approve/decline buttons,
  which `a`/`d` cover); pages scroll to the focused control (`revealFocus`). Escape
  leaves a control before leaving the page (list, approval form). New keys
  go in `model/keymap.js` (with a test), read letters in lower case with
  their capital variant decided by Shift alone (Caps Lock must never turn
  `a` into a quick approval), and are carried out in
  `panel/Keyboard.qml`. Each page pins a `KeyHints` line listing its keys:
  update it with any new shortcut.
- **Pure logic goes in `model/`**, in the file of its topic, with tests in
  `tests/<module>.test.js`. QML keeps what needs Qt: measuring, focus,
  locale formatting, translations, the network. A model file reaches
  another only through `.import "other.js" as Other` and `Other.fn`.
- **QML files import only the model files they use**, each under its
  capitalised name (`import "../model/requests.js" as Requests`); keys.js
  would clash with QML's `Keys`, hence `keymap.js` as `KeyMap`.
- **Who gets what.** `ui/` components are display-only: everything comes in
  as explicit properties (colours and font included) and goes out as
  signals; they never see the panel or the service. Pages take the panel as
  `required property var ctx`. `panel/` objects are per panel (one per
  monitor), never singletons: shared state belongs in the service.
  `service/` parts get their dependencies as required properties set by
  `Service.qml`, never by reaching up.
- **No file named like a type of the kit (`qs.Ui`) or Quickshell**
  (`Button`, `TextField`, `ConfirmDialog`, `Process`, …): files import
  both their folder and those modules, and the name would then depend on
  which one wins. `Panel.qml`, built on the kit's `Panel`, is the
  manifest's entry point; leave it be, but add no other.

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
