import QtQuick
import Quickshell.Io
import "../model/Seerr.js" as Seerr

// The API key, kept in the keyring (secret-tool) under the origin of the
// URL it was entered for. Each lookup ends with `loaded`, after which the
// connection starts over with the key found, or without one.
QtObject {
  id: keyring
  // The service: the origin of its URL, translations.
  required property var svc

  // "loading" | "missing" | "ok" | "error"
  property string state: "loading"
  property string message: ""
  property string _apiKey: ""
  // The origin _apiKey was read for. The key is only sent to a URL of that
  // origin, so a URL change can never carry it to another server.
  property string _keyOrigin: ""
  property bool _keyReloadQueued: false
  property string _pendingKey: ""

  signal loaded()

  // Whether the key may go to `url`. Computed from the URL itself, never from
  // the keyOrigin binding: during a URL change, onBaseUrlChanged can run
  // before that binding catches up, and the old key would leave for the new
  // server.
  function matches(url) {
    return state === "ok" && _apiKey !== "" && _keyOrigin !== "" && !!url && Seerr.keyOrigin(url) === _keyOrigin
  }

  // The key, for a call to `url` only.
  function keyFor(url) {
    return matches(url) ? _apiKey : ""
  }

  function valid(key) {
    return /^[A-Za-z0-9+\/=_-]{8,256}$/.test(String(key || ""))
  }

  // Reads the key stored for the current origin. A lookup already running
  // for another origin is followed by a fresh one rather than trusted.
  function load() {
    if (keyLookup.running) { _keyReloadQueued = true; return }
    _keyReloadQueued = false
    _apiKey = ""
    _keyOrigin = ""
    if (!svc.keyOrigin) {
      state = "missing"
      message = ""
      loaded()
      return
    }
    state = "loading"
    keyLookup.origin = svc.keyOrigin
    keyLookup.running = true
  }

  // Returns false when the key is malformed or there is no URL to bind it
  // to; the result arrives through state / message.
  function store(key) {
    var k = String(key || "").trim()
    if (!svc.keyOrigin) { message = svc.t("key.needUrl"); return false }
    if (!valid(k)) { message = svc.t("key.invalid"); return false }
    if (keyStore.running) { message = svc.t("key.busy"); return false }
    _pendingKey = k
    message = ""
    keyStore.origin = svc.keyOrigin
    keyStore.running = true
    return true
  }

  // Removes the key of the current origin only.
  function clear() {
    if (keyClear.running || !svc.keyOrigin) return
    keyClear.origin = svc.keyOrigin
    keyClear.running = true
  }

  property Process _lookup: Process {
    id: keyLookup
    property string origin: ""
    command: ["secret-tool", "lookup", "service", Seerr.PLUGIN_ID, "account", "api-key", "origin", origin]
    stdout: StdioCollector { id: keyLookupOut; waitForEnd: true }
    stderr: StdioCollector { id: keyLookupErr; waitForEnd: true }
    onExited: function(code) {
      // The URL changed while this ran: its answer belongs to another server.
      if (keyring._keyReloadQueued || keyLookup.origin !== keyring.svc.keyOrigin) {
        Qt.callLater(keyring.load)
        return
      }
      var key = String(keyLookupOut.text || "").trim()
      if (code === 0 && keyring.valid(key)) {
        keyring._apiKey = key
        keyring._keyOrigin = keyLookup.origin
        keyring.state = "ok"
        keyring.message = ""
      } else {
        keyring._apiKey = ""
        keyring._keyOrigin = ""
        // secret-tool exits 1 with no output when nothing is stored.
        var err = String(keyLookupErr.text || "").trim()
        keyring.state = code === 1 && err === "" && key === "" ? "missing" : "error"
        keyring.message = keyring.state === "error" ? (err ? Seerr.str(err, 200) : keyring.svc.t("key.lookupFailed")) : ""
      }
      keyring.loaded()
    }
  }

  // The key travels on stdin, never in argv where /proc would show it.
  property Process _store: Process {
    id: keyStore
    property string origin: ""
    command: ["secret-tool", "store", "--label=OmaSeerr (Seerr API key for " + origin + ")",
      "service", Seerr.PLUGIN_ID, "account", "api-key", "origin", origin]
    stdinEnabled: true
    stderr: StdioCollector { id: keyStoreErr; waitForEnd: true }
    onStarted: {
      write(keyring._pendingKey)
      keyring._pendingKey = ""
      keyStore.stdinEnabled = false
    }
    onExited: function(code) {
      keyStore.stdinEnabled = true
      if (code !== 0) {
        keyring.message = Seerr.str(String(keyStoreErr.text || "").trim(), 200) || keyring.svc.t("key.storeFailed")
        return
      }
      keyring.message = ""
      keyring.load()
    }
  }

  property Process _clear: Process {
    id: keyClear
    property string origin: ""
    command: ["secret-tool", "clear", "service", Seerr.PLUGIN_ID, "account", "api-key", "origin", origin]
    onExited: function() { keyring.load() }
  }
}
