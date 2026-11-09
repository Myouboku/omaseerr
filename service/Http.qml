import QtQuick
import Quickshell.Io
import "../model/Seerr.js" as Seerr

// Calls to Seerr's API: a pool of curl processes, at most maxParallel at a
// time, each bounded in time. Every call belongs to a connection; reset()
// starts a new one and drops what the old one still had going.
QtObject {
  id: http
  // The service: the URL calls go to.
  required property var svc
  // The API key, and which URL it may go to.
  required property var keyring

  property int generation: 0
  // Calls waiting for a slot, and calls whose curl is running.
  property var _queue: []
  property var _inflight: []
  readonly property int maxParallel: 6
  readonly property int requestTimeoutSec: 15

  // cb({ ok, status, data, error, message, location }). Callbacks from a
  // superseded connection (URL or key changed meanwhile) are dropped. The
  // request runs through curl, which does not follow redirects: see
  // Seerr.curlConfig.
  function api(method, path, body, cb) {
    // Checked against the very URL requested below.
    var target = svc.baseUrl
    if (!keyring.matches(target)) {
      cb({ ok: false, status: 0, error: "notConfigured" })
      return
    }
    var generation = http.generation
    var call = {
      config: Seerr.curlConfig(method, target + Seerr.API_PREFIX + path, keyring.keyFor(target), body),
      proc: null, deadline: 0, done: false, finish: null
    }
    call.finish = function(result) {
      if (call.done) return
      call.done = true
      call.config = ""
      var at = http._inflight.indexOf(call)
      if (at !== -1) http._inflight.splice(at, 1)
      Qt.callLater(http.pump)
      if (generation !== http.generation) return
      cb(result)
    }
    _queue.push(call)
    pump()
  }

  // Starts queued calls while there is room.
  function pump() {
    while (_inflight.length < maxParallel && _queue.length > 0) {
      var call = _queue.shift()
      if (call.done) continue
      call.deadline = Date.now() + (requestTimeoutSec + 5) * 1000
      call.proc = curlProcess.createObject(http, { call: call, command: Seerr.curlArgv(requestTimeoutSec) })
      if (!call.proc) { call.finish({ ok: false, status: 0, error: "network" }); continue }
      _inflight.push(call)
      call.proc.running = true
      watchdog.running = true
    }
  }

  // A new connection: calls of the previous one never answer.
  function reset() {
    generation++
    abortAll()
  }

  function abortAll() {
    var queued = _queue
    _queue = []
    for (var i = 0; i < queued.length; i++) queued[i].done = true
    var calls = _inflight.slice()
    _inflight = []
    for (var j = 0; j < calls.length; j++) {
      calls[j].done = true
      calls[j].config = ""
      if (calls[j].proc) calls[j].proc.running = false
    }
  }

  property Component _curl: Component {
    id: curlProcess
    Process {
      id: proc
      property var call: null
      stdinEnabled: true
      stdout: StdioCollector { id: curlOut; waitForEnd: true }
      onStarted: {
        // The config, key included, goes in on stdin; closing it ends the read.
        if (proc.call && !proc.call.done) write(proc.call.config)
        proc.stdinEnabled = false
      }
      onExited: function(code) {
        var call = proc.call
        proc.call = null
        if (call) call.finish(Seerr.parseCurlResult(code, String(curlOut.text || "")))
        Qt.callLater(function() { proc.destroy() })
      }
    }
  }

  // curl has its own --max-time; this only catches a process that never ends.
  property Timer _watchdog: Timer {
    id: watchdog
    interval: 1000
    repeat: true
    onTriggered: {
      var now = Date.now()
      var calls = http._inflight.slice()
      for (var i = 0; i < calls.length; i++) {
        if (calls[i].deadline > now) continue
        if (calls[i].proc) calls[i].proc.running = false
        calls[i].finish({ ok: false, status: 0, error: "timeout" })
      }
      if (http._inflight.length === 0) watchdog.running = false
    }
  }
}
