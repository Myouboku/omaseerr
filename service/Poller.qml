import QtQuick
import "../model/Seerr.js" as Seerr

// Asks Seerr every refreshIntervalSec what changed: the counts, the
// pending requests (new ones are announced) and, when asked to, the
// statuses of recent requests. After an error it retries the connection
// instead.
QtObject {
  id: poller
  // The service: settings, URL, open panels.
  required property var svc
  required property var http
  // The connection, its state, and where errors go.
  required property var conn
  // The list, refreshed with each poll while a panel is open.
  required property var store
  // Ids seen and statuses, saved across restarts.
  required property var stateFile

  property var counts: Seerr.normalizeCounts(null)
  property bool _polling: false

  // New pending requests, newest first, worth announcing.
  signal arrived(var requests)
  // A recent request became available or failed.
  signal statusReached(var request, string statusKey)

  property Timer _timer: Timer {
    id: pollTimer
    interval: poller.svc.settings.refreshIntervalSec * 1000
    repeat: true
    running: poller.conn.state === "connected" || poller.conn.state === "error"
    onTriggered: {
      if (poller.conn.state === "error") poller.conn.reconnect(true)
      else poller.poll()
    }
  }

  // A new connection: a poll still running will never answer.
  function stop() {
    _polling = false
  }

  function clear() {
    counts = Seerr.normalizeCounts(null)
  }

  function refresh() {
    if (conn.state !== "connected") { conn.reconnect(true); return }
    poll()
    if (svc.openPanels > 0) store.reloadList()
  }

  function poll() {
    if (conn.state !== "connected" || _polling) return
    _polling = true
    http.api("GET", "/request/count", null, function(res) {
      if (!res.ok) { poller._polling = false; poller.conn.fail(res); return }
      poller.counts = Seerr.normalizeCounts(res.data)
      poller.conn.lastOkAt = Date.now()
      poller.pollPending()
    })
  }

  function pollPending() {
    http.api("GET", Seerr.listPath({ filter: "pending", take: 50, skip: 0, sort: "added", sortDirection: "desc", mediaType: "all" }), null, function(res) {
      if (!res.ok) { poller._polling = false; poller.conn.fail(res); return }
      var pending = Seerr.normalizeRequestList(res.data).requests
      poller.handlePending(pending)
      // Before the saved state is read, comparing statuses (and saving them)
      // would write over it.
      if (poller.svc.settings.notifyStatusChanges && poller.stateFile.loaded) poller.pollStatuses()
      else {
        poller._polling = false
        if (poller.svc.openPanels > 0) poller.store.refreshListQuietly()
      }
    })
  }

  function pollStatuses() {
    http.api("GET", Seerr.listPath({ filter: "all", take: 50, skip: 0, sort: "modified", sortDirection: "desc", mediaType: "all" }), null, function(res) {
      poller._polling = false
      if (!res.ok) { poller.conn.fail(res); return }
      var recent = Seerr.normalizeRequestList(res.data).requests
      var changes = Seerr.statusChanges(poller.stateFile.state.statuses, recent)
      var next = Seerr.statusMap(recent)
      var st = poller.stateFile.state
      poller.stateFile.state = { url: st.url, seen: st.seen, statuses: next, primed: st.primed }
      poller.stateFile.save()
      if (st.primed) {
        for (var i = 0; i < changes.length; i++) {
          var req = null
          for (var j = 0; j < recent.length; j++) if (recent[j].id === changes[i].id) req = recent[j]
          if (req) poller.statusReached(req, changes[i].to)
        }
      }
      if (poller.svc.openPanels > 0) poller.store.refreshListQuietly()
    })
  }

  function handlePending(pending) {
    if (!stateFile.loaded) return
    var st = stateFile.state
    var firstRun = !st.primed || st.url !== svc.baseUrl
    var fresh = Seerr.newRequestIds(firstRun ? [] : st.seen, pending)
    var seen = Seerr.rememberIds(firstRun ? [] : st.seen, pending.map(function(r) { return r.id }))
    stateFile.state = { url: svc.baseUrl, seen: seen, statuses: firstRun ? Seerr.statusMap(pending) : st.statuses, primed: true }
    stateFile.save()
    // Requests already pending on a first connection to a server were not
    // missed: they are only recorded as seen.
    if (firstRun) return
    var announce = pending.filter(function(r) { return fresh.indexOf(r.id) !== -1 })
    if (announce.length === 0) return
    arrived(announce)
  }
}
