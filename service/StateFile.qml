import QtQuick
import Quickshell
import Quickshell.Io
import "../model/Seerr.js" as Seerr

// What survives a restart, in state.json: the request ids already seen and
// their last statuses, so nothing is announced twice. Also makes the
// folders it and the notification posters live in.
QtObject {
  id: stateFile

  // { url, seen, statuses, primed }: see Seerr.parseState.
  property var state: Seerr.parseState("")
  property bool loaded: false

  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omaseerr"
  readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/omaseerr"
  property bool dirsReady: false

  // The saved state was read (not on a failed read).
  signal read()

  function prepare() {
    prepareDirs.running = true
  }

  function save() {
    // Saving before the file was read would replace what it holds.
    if (!dirsReady || !loaded) return
    saveTimer.restart()
  }

  property Process _prepare: Process {
    id: prepareDirs
    command: ["bash", "-c",
      "umask 077\n" +
      "mkdir -p -- \"$1\" \"$2/posters\" && chmod 700 -- \"$1\" || exit 1\n" +
      "f=$1/state.json\n" +
      "[[ -L $f ]] && rm -f -- \"$f\"\n" +
      "[[ -e $f ]] || : >\"$f\"\n" +
      "find \"$2/posters\" -type f -mtime +30 -delete 2>/dev/null\n" +
      "exit 0",
      "omaseerr-state", stateFile.stateDir, stateFile.cacheDir]
    onExited: function(code) { stateFile.dirsReady = code === 0 }
  }

  property FileView _file: FileView {
    id: file
    path: stateFile.dirsReady ? stateFile.stateDir + "/state.json" : ""
    atomicWrites: true
    printErrors: false
    onLoaded: {
      stateFile.state = Seerr.parseState(text())
      stateFile.loaded = true
      stateFile.read()
    }
    onLoadFailed: {
      stateFile.state = Seerr.parseState("")
      stateFile.loaded = true
    }
  }

  property Timer _save: Timer {
    id: saveTimer
    interval: 500
    onTriggered: {
      var st = stateFile.state
      file.setText(JSON.stringify({ url: st.url, seen: st.seen, statuses: st.statuses, primed: st.primed }) + "\n")
    }
  }
}
