import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import "model/Seerr.js" as Seerr

// The one OmaSeerr instance per shell. It owns the connection (URL from the
// bar entry's settings, API key from the keyring), polls Seerr, announces new
// requests, runs the request actions, and answers IPC. Bar widgets — one per
// monitor — only draw what this holds, so nothing here is ever doubled.
Item {
  id: root

  // Injected by the shell.
  property var shell: null
  property var manifest: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"

  readonly property string pluginId: Seerr.PLUGIN_ID

  // ---------------------------------------------------------------- settings

  // Our entry in the bar layout is where the settings live. The bar hands the
  // widget its entry live on every change, and the widget passes it here; the
  // copy of the bar config the shell gave the service is only refreshed when
  // plugins reload, so it serves only until a widget reports in.
  property var widgetSettings: null
  readonly property var entry: widgetSettings ? widgetSettings
    : (shell && shell.barConfig ? Seerr.findBarEntry(shell.barConfig, pluginId) : null)
  readonly property var settings: Seerr.normalizeSettings(entry || {})
  readonly property string baseUrl: settings.url
  // Where the API key may go: the keyring holds one key per origin.
  readonly property string keyOrigin: Seerr.keyOrigin(baseUrl)
  readonly property bool insecure: baseUrl.indexOf("http://") === 0
  // Plain HTTP to something outside the local network: worth a warning.
  readonly property bool exposed: insecure && !Seerr.isPrivateHost(baseUrl)
  readonly property bool canSaveSettings: !!shell && typeof shell.updateEntryInline === "function"

  function saveSettings(patch) {
    if (!canSaveSettings) return false
    var next = {}
    var current = entry || {}
    for (var k in current) if (k !== "id") next[k] = current[k]
    for (var p in patch) next[p] = patch[p]
    return shell.updateEntryInline(pluginId, next)
  }

  // ---------------------------------------------------------------- i18n

  Commons.Translations {
    id: catalog
    directory: Qt.resolvedUrl("i18n")
  }
  // Exposed so the panels translate from the same catalog.
  readonly property var strings: catalog
  function t(key) { return catalog.t(key) }
  function tn(key, n) { return catalog.tn(key, n).arg(Commons.I18n.formatNumber(n)) }

  // ---------------------------------------------------------------- state

  // "unconfigured" | "connecting" | "connected" | "error"
  property string connection: "unconfigured"
  property string lastError: ""
  property var me: null
  property bool canManage: true
  property var counts: Seerr.normalizeCounts(null)
  readonly property int pendingCount: counts.pending

  // "loading" | "missing" | "ok" | "error"
  property string keyState: "loading"
  property string keyMessage: ""
  property string _apiKey: ""
  // The origin _apiKey was read for. The key is only sent to a URL of that
  // origin, so a URL change can never carry it to another server.
  property string _keyOrigin: ""
  property bool _keyReloadQueued: false
  // Whether the key may go to `url`. Computed from the URL itself, never from
  // the keyOrigin binding: during a URL change, onBaseUrlChanged can run
  // before that binding catches up, and the old key would leave for the new
  // server.
  function keyMatches(url) {
    return keyState === "ok" && _apiKey !== "" && _keyOrigin !== "" && !!url && Seerr.keyOrigin(url) === _keyOrigin
  }
  property string _pendingKey: ""

  // Panels open across monitors; while any is, the list follows each poll.
  property int openPanels: 0
  // A request a notification or IPC asked to show; the panel that opens
  // takes it and clears it.
  property int focusRequestId: 0

  // The panel's list.
  property var view: ({
    filter: settings.defaultFilter,
    mediaType: settings.defaultMediaType,
    sort: settings.defaultSort,
    sortDirection: settings.defaultSortDirection,
    search: ""
  })
  property var rows: []
  property int rowsTotal: 0
  property bool listLoading: false
  property string listError: ""
  property int _listSkip: 0
  property int _listGeneration: 0
  readonly property bool hasMore: _listSkip < rowsTotal

  // tmdb details by Seerr.mediaKey; mediaRevision bumps on every arrival so
  // bindings reading media through mediaFor() re-evaluate.
  property var media: ({})
  property int mediaRevision: 0
  property var _mediaWaiters: ({})

  // The latest version of every request seen, so a detail view keeps up
  // after the request leaves the filtered list (approved, declined…).
  property var _known: ({})
  property int knownRevision: 0

  function remember(list) {
    var known = _known
    if (Object.keys(known).length > 500) known = ({})
    for (var i = 0; i < list.length; i++) if (list[i]) known[list[i].id] = list[i]
    _known = known
    knownRevision++
  }

  function forget(id) {
    delete _known[id]
    knownRevision++
  }

  function requestById(id) {
    if (knownRevision < 0) return null
    return _known[id] || null
  }

  // Request ids with an action in flight.
  property var busy: ({})

  // Seen ids and last statuses, persisted so a restart does not re-announce.
  property var _state: Seerr.parseState("")
  property bool _stateLoaded: false

  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omaseerr"
  readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/omaseerr"
  property bool dirsReady: false

  signal actionDone(int requestId, string action, bool ok, string message)

  // ---------------------------------------------------------------- lifecycle

  Component.onCompleted: {
    prepareDirs.running = true
    loadKey()
  }

  onBaseUrlChanged: reconnect()
  // Another server: its key, or none, never the previous one's.
  onKeyOriginChanged: loadKey()

  // A language switch changes the titles Seerr hands back.
  Connections {
    target: Commons.I18n
    function onLanguageChanged() {
      root.media = ({})
      root.mediaRevision++
      if (root.openPanels > 0) root.reloadList()
    }
  }

  // A change to the default filter or sort resets the list to it.
  property string _defaultsKey: ""
  onSettingsChanged: {
    var key = [settings.defaultFilter, settings.defaultMediaType, settings.defaultSort, settings.defaultSortDirection].join("|")
    if (_defaultsKey !== "" && key !== _defaultsKey) {
      resetView()
      if (openPanels > 0) reloadList()
    }
    _defaultsKey = key
  }

  function resetView() {
    view = {
      filter: settings.defaultFilter,
      mediaType: settings.defaultMediaType,
      sort: settings.defaultSort,
      sortDirection: settings.defaultSortDirection,
      search: ""
    }
  }

  function reconnect() {
    _generation++
    abortAll()
    _polling = false
    listLoading = false
    busy = ({})
    _known = ({})
    knownRevision++
    me = null
    counts = Seerr.normalizeCounts(null)
    rows = []
    rowsTotal = 0
    _listSkip = 0
    media = ({})
    mediaRevision++
    // The calls these waited on were just dropped and will never answer;
    // left in place, they would keep their media from ever loading again.
    _mediaWaiters = ({})
    // Another server has other Radarr/Sonarr servers, profiles and folders.
    _servers = ({})
    _serverDetails = ({})
    if (!keyMatches(baseUrl)) {
      connection = "unconfigured"
      lastError = ""
      return
    }
    connection = "connecting"
    lastError = ""
    api("GET", "/auth/me", null, function(res) {
      if (!res.ok) { fail(res); return }
      root.me = Seerr.normalizeUser(res.data)
      var perms = res.data && typeof res.data.permissions === "number" ? res.data.permissions : 0
      // ADMIN (2) or MANAGE_REQUESTS (16).
      root.canManage = (perms & 2) !== 0 || (perms & 16) !== 0
      root.connection = "connected"
      root.lastError = ""
      root.poll()
      if (root.openPanels > 0) root.reloadList()
    })
  }

  function fail(res) {
    connection = "error"
    lastError = describeError(res)
  }

  function describeError(res) {
    if (!res) return t("error.unknown")
    if (res.error === "notConfigured") return t("error.notConfigured")
    if (res.error === "timeout") return t("error.timeout")
    if (res.error === "network") return t("error.network")
    if (res.error === "badJson" || res.error === "tooLarge") return t("error.badResponse")
    if (res.error === "tls") return t("error.tls")
    if (res.error === "notPending") return t("error.conflict")
    if (res.error === "otherServer") return t("error.otherServer")
    if (res.error === "redirect") return res.location ? t("error.redirectTo").arg(res.location) : t("error.redirect")
    if (res.status === 401 || res.status === 403) return t("error.unauthorized")
    if (res.status === 404) return t("error.notFound")
    if (res.status === 409) return res.message || t("error.conflict")
    return res.message ? res.message : t("error.http").arg(res.status)
  }

  // ---------------------------------------------------------------- keyring

  function validKey(key) {
    return /^[A-Za-z0-9+\/=_-]{8,256}$/.test(String(key || ""))
  }

  // Reads the key stored for the current origin. A lookup already running
  // for another origin is followed by a fresh one rather than trusted.
  function loadKey() {
    if (keyLookup.running) { _keyReloadQueued = true; return }
    _keyReloadQueued = false
    _apiKey = ""
    _keyOrigin = ""
    if (!keyOrigin) {
      keyState = "missing"
      keyMessage = ""
      reconnect()
      return
    }
    keyState = "loading"
    keyLookup.origin = keyOrigin
    keyLookup.running = true
  }

  // Returns false when the key is malformed or there is no URL to bind it
  // to; the result arrives through keyState / keyMessage.
  function storeKey(key) {
    var k = String(key || "").trim()
    if (!keyOrigin) { keyMessage = t("key.needUrl"); return false }
    if (!validKey(k)) { keyMessage = t("key.invalid"); return false }
    if (keyStore.running) { keyMessage = t("key.busy"); return false }
    _pendingKey = k
    keyMessage = ""
    keyStore.origin = keyOrigin
    keyStore.running = true
    return true
  }

  // Removes the key of the current origin only.
  function clearKey() {
    if (keyClear.running || !keyOrigin) return
    keyClear.origin = keyOrigin
    keyClear.running = true
  }

  Process {
    id: keyLookup
    property string origin: ""
    command: ["secret-tool", "lookup", "service", Seerr.PLUGIN_ID, "account", "api-key", "origin", origin]
    stdout: StdioCollector { id: keyLookupOut; waitForEnd: true }
    stderr: StdioCollector { id: keyLookupErr; waitForEnd: true }
    onExited: function(code) {
      // The URL changed while this ran: its answer belongs to another server.
      if (root._keyReloadQueued || keyLookup.origin !== root.keyOrigin) {
        Qt.callLater(root.loadKey)
        return
      }
      var key = String(keyLookupOut.text || "").trim()
      if (code === 0 && root.validKey(key)) {
        root._apiKey = key
        root._keyOrigin = keyLookup.origin
        root.keyState = "ok"
        root.keyMessage = ""
      } else {
        root._apiKey = ""
        root._keyOrigin = ""
        // secret-tool exits 1 with no output when nothing is stored.
        var err = String(keyLookupErr.text || "").trim()
        root.keyState = code === 1 && err === "" && key === "" ? "missing" : "error"
        root.keyMessage = root.keyState === "error" ? (err ? Seerr.str(err, 200) : root.t("key.lookupFailed")) : ""
      }
      root.reconnect()
    }
  }

  // The key travels on stdin, never in argv where /proc would show it.
  Process {
    id: keyStore
    property string origin: ""
    command: ["secret-tool", "store", "--label=OmaSeerr (Seerr API key for " + origin + ")",
      "service", Seerr.PLUGIN_ID, "account", "api-key", "origin", origin]
    stdinEnabled: true
    stderr: StdioCollector { id: keyStoreErr; waitForEnd: true }
    onStarted: {
      write(root._pendingKey)
      root._pendingKey = ""
      keyStore.stdinEnabled = false
    }
    onExited: function(code) {
      keyStore.stdinEnabled = true
      if (code !== 0) {
        root.keyMessage = Seerr.str(String(keyStoreErr.text || "").trim(), 200) || root.t("key.storeFailed")
        return
      }
      root.keyMessage = ""
      root.loadKey()
    }
  }

  Process {
    id: keyClear
    property string origin: ""
    command: ["secret-tool", "clear", "service", Seerr.PLUGIN_ID, "account", "api-key", "origin", origin]
    onExited: function() { root.loadKey() }
  }

  // ---------------------------------------------------------------- HTTP

  property int _generation: 0
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
    var target = baseUrl
    if (!keyMatches(target)) {
      cb({ ok: false, status: 0, error: "notConfigured" })
      return
    }
    var generation = _generation
    var call = {
      config: Seerr.curlConfig(method, target + Seerr.API_PREFIX + path, _apiKey, body),
      proc: null, deadline: 0, done: false, finish: null
    }
    call.finish = function(result) {
      if (call.done) return
      call.done = true
      call.config = ""
      var at = root._inflight.indexOf(call)
      if (at !== -1) root._inflight.splice(at, 1)
      Qt.callLater(root.pump)
      if (generation !== root._generation) return
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
      call.proc = curlProcess.createObject(root, { call: call, command: Seerr.curlArgv(requestTimeoutSec) })
      if (!call.proc) { call.finish({ ok: false, status: 0, error: "network" }); continue }
      _inflight.push(call)
      call.proc.running = true
      watchdog.running = true
    }
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

  Component {
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
  Timer {
    id: watchdog
    interval: 1000
    repeat: true
    onTriggered: {
      var now = Date.now()
      var calls = root._inflight.slice()
      for (var i = 0; i < calls.length; i++) {
        if (calls[i].deadline > now) continue
        if (calls[i].proc) calls[i].proc.running = false
        calls[i].finish({ ok: false, status: 0, error: "timeout" })
      }
      if (root._inflight.length === 0) watchdog.running = false
    }
  }

  // ---------------------------------------------------------------- polling

  Timer {
    id: pollTimer
    interval: root.settings.refreshIntervalSec * 1000
    repeat: true
    running: root.connection === "connected" || root.connection === "error"
    onTriggered: {
      if (root.connection === "error") root.reconnect()
      else root.poll()
    }
  }

  property bool _polling: false

  function refresh() {
    if (connection !== "connected") { reconnect(); return }
    poll()
    if (openPanels > 0) reloadList()
  }

  function poll() {
    if (connection !== "connected" || _polling) return
    _polling = true
    api("GET", "/request/count", null, function(res) {
      if (!res.ok) { root._polling = false; root.fail(res); return }
      root.counts = Seerr.normalizeCounts(res.data)
      root.pollPending()
    })
  }

  function pollPending() {
    api("GET", Seerr.listPath({ filter: "pending", take: 50, skip: 0, sort: "added", sortDirection: "desc", mediaType: "all" }), null, function(res) {
      if (!res.ok) { root._polling = false; root.fail(res); return }
      var pending = Seerr.normalizeRequestList(res.data).requests
      root.handlePending(pending)
      // Before the saved state is read, comparing statuses (and saving them)
      // would write over it.
      if (root.settings.notifyStatusChanges && root._stateLoaded) root.pollStatuses()
      else {
        root._polling = false
        if (root.openPanels > 0) root.refreshListQuietly()
      }
    })
  }

  function pollStatuses() {
    api("GET", Seerr.listPath({ filter: "all", take: 50, skip: 0, sort: "modified", sortDirection: "desc", mediaType: "all" }), null, function(res) {
      root._polling = false
      if (!res.ok) { root.fail(res); return }
      var recent = Seerr.normalizeRequestList(res.data).requests
      var changes = Seerr.statusChanges(root._state.statuses, recent)
      var next = Seerr.statusMap(recent)
      var st = root._state
      root._state = { url: st.url, seen: st.seen, statuses: next, primed: st.primed }
      root.saveState()
      if (st.primed) {
        for (var i = 0; i < changes.length; i++) {
          var req = null
          for (var j = 0; j < recent.length; j++) if (recent[j].id === changes[i].id) req = recent[j]
          if (req) root.announceStatus(req, changes[i].to)
        }
      }
      if (root.openPanels > 0) root.refreshListQuietly()
    })
  }

  function handlePending(pending) {
    if (!_stateLoaded) return
    var st = _state
    var firstRun = !st.primed || st.url !== baseUrl
    var fresh = Seerr.newRequestIds(firstRun ? [] : st.seen, pending)
    var seen = Seerr.rememberIds(firstRun ? [] : st.seen, pending.map(function(r) { return r.id }))
    _state = { url: baseUrl, seen: seen, statuses: firstRun ? Seerr.statusMap(pending) : st.statuses, primed: true }
    saveState()
    if (!settings.notifyNewRequests) return
    if (firstRun && !settings.notifyOnStartup) return
    var announce = pending.filter(function(r) { return fresh.indexOf(r.id) !== -1 })
    if (announce.length === 0) return
    // A threshold of 1 means never group.
    var threshold = settings.notifyGroupThreshold
    if (threshold > 1 && announce.length >= threshold) announceMany(announce)
    else for (var i = announce.length - 1; i >= 0; i--) announceNew(announce[i])
  }

  // ---------------------------------------------------------------- list

  function setView(patch) {
    var next = {}
    for (var k in view) next[k] = view[k]
    for (var p in patch) next[p] = patch[p]
    var refetch = next.filter !== view.filter || next.mediaType !== view.mediaType
      || next.sort !== view.sort || next.sortDirection !== view.sortDirection
    view = next
    if (refetch) reloadList()
  }

  function pageSize() {
    // The declined filter pages through everything, so it asks for more.
    return view.filter === "declined" ? 100 : settings.pageSize
  }

  function reloadList() {
    _listGeneration++
    _listSkip = 0
    rowsTotal = 0
    listError = ""
    fetchPage(true)
  }

  function loadMore() {
    if (listLoading || !hasMore) return
    fetchPage(false)
  }

  // Refetches what is on screen without clearing it first. One call brings
  // at most 100 rows: past that, the head is refreshed and the rows already
  // scrolled to stay, rather than the list shrinking back on every poll.
  function refreshListQuietly() {
    if (listLoading || connection !== "connected") return
    var generation = ++_listGeneration
    var take = Math.min(100, Math.max(pageSize(), rows.length))
    api("GET", Seerr.listPath({ filter: view.filter, mediaType: view.mediaType, sort: view.sort, sortDirection: view.sortDirection, take: take, skip: 0 }), null, function(res) {
      if (generation !== root._listGeneration || !res.ok) return
      var page = Seerr.normalizeRequestList(res.data)
      root.remember(page.requests)
      if (root.rows.length > take) {
        root.rows = Seerr.mergePage(page.requests, root.rows.slice(take))
      } else {
        root.rows = page.requests
        root._listSkip = page.requests.length
      }
      root.rowsTotal = page.total
      root.fetchMediaFor(page.requests)
    })
  }

  // The declined filter is applied here, over pages of every request: when
  // the pages so far hold too few declined ones to fill the panel, the next
  // page is fetched on its own, since there is nothing to scroll to ask for
  // it. Bounded, so a server with few declined requests is not read whole.
  readonly property int declinedScanLimit: 1000
  function continueDeclinedScan() {
    if (view.filter !== "declined" || !hasMore || rows.length >= declinedScanLimit) return
    var found = 0
    for (var i = 0; i < rows.length; i++) if (rows[i].status === Seerr.REQUEST_DECLINED) found++
    if (found < settings.pageSize) Qt.callLater(loadMore)
  }

  function fetchPage(reset) {
    if (connection !== "connected") { if (reset) rows = []; return }
    var generation = _listGeneration
    var skip = reset ? 0 : _listSkip
    listLoading = true
    api("GET", Seerr.listPath({ filter: view.filter, mediaType: view.mediaType, sort: view.sort, sortDirection: view.sortDirection, take: pageSize(), skip: skip }), null, function(res) {
      if (generation !== root._listGeneration) return
      root.listLoading = false
      if (!res.ok) { root.listError = root.describeError(res); return }
      var page = Seerr.normalizeRequestList(res.data)
      root.remember(page.requests)
      root.rows = reset ? page.requests : Seerr.mergePage(root.rows, page.requests)
      root.rowsTotal = page.total
      root._listSkip = skip + page.requests.length
      root.listError = ""
      root.fetchMediaFor(page.requests)
      root.continueDeclinedScan()
    })
  }

  function rowById(id) {
    for (var i = 0; i < rows.length; i++) if (rows[i].id === id) return rows[i]
    return null
  }

  function updateRow(req) {
    var found = false
    for (var i = 0; i < rows.length; i++) if (rows[i].id === req.id) found = true
    if (found) rows = Seerr.replaceRequest(rows, req)
  }

  // Fetches one request (for IPC/notification paths that may not have it).
  function fetchRequest(id, cb) {
    api("GET", "/request/" + id, null, function(res) {
      var req = res.ok ? Seerr.normalizeRequest(res.data) : null
      if (req) root.remember([req])
      cb(req, res)
    })
  }

  // ---------------------------------------------------------------- media

  function mediaFor(req) {
    // Reading mediaRevision makes callers' bindings follow new arrivals.
    if (mediaRevision < 0 || !req) return null
    return media[Seerr.mediaKey(req.type, req.tmdbId)] || null
  }

  function fetchMediaFor(list) {
    for (var i = 0; i < list.length; i++) ensureMedia(list[i], null)
  }

  function ensureMedia(req, cb) {
    if (!req || !req.tmdbId) { if (cb) cb(null); return }
    var key = Seerr.mediaKey(req.type, req.tmdbId)
    if (media[key]) { if (cb) cb(media[key]); return }
    var waiting = _mediaWaiters[key]
    if (waiting) { if (cb) waiting.push(cb); return }
    _mediaWaiters[key] = cb ? [cb] : []
    var lang = String(Commons.I18n.language || "en")
    api("GET", Seerr.mediaPath(req.type, req.tmdbId) + "?language=" + encodeURIComponent(lang), null, function(res) {
      var waiters = root._mediaWaiters[key] || []
      delete root._mediaWaiters[key]
      var value = res.ok ? Seerr.normalizeMedia(res.data, req.type) : null
      if (value) {
        var next = root.media
        next[key] = value
        root.media = next
        root.mediaRevision++
      }
      for (var i = 0; i < waiters.length; i++) waiters[i](value)
    })
  }

  function titleFor(req) {
    var m = mediaFor(req)
    if (m && m.title) return m.year ? m.title + " (" + m.year + ")" : m.title
    return req ? (req.type === "tv" ? t("type.tv") : t("type.movie")) + " #" + req.tmdbId : ""
  }

  function openInBrowser(req) {
    if (!baseUrl) return
    var url = req ? Seerr.webUrl(baseUrl, req.type, req.tmdbId) : baseUrl + "/requests"
    Qt.openUrlExternally(url)
  }

  // ---------------------------------------------------------------- actions

  function isBusy(id) { return busy[id] === true }

  function setBusy(id, on) {
    var next = {}
    for (var k in busy) if (busy[k]) next[k] = true
    if (on) next[id] = true
    else delete next[id]
    busy = next
  }

  function afterAction(id, action, res, updated, notify) {
    setBusy(id, false)
    var ok = res.ok
    var message = ok ? "" : describeError(res)
    if (ok) {
      if (action === "delete") {
        rows = Seerr.removeRequest(rows, id)
        forget(id)
      } else if (updated) {
        remember([updated])
        updateRow(updated)
        // A row that left the current filter goes once the list refreshes.
      }
      poll()
      if (openPanels > 0) refreshListQuietly()
    }
    actionDone(id, action, ok, message)
    if (notify) announceResult(id, action, ok, message, updated)
  }

  // Seerr's own defaults: no form, straight to approve.
  function quickApprove(id, notify) {
    id = Seerr.positiveId(id)
    if (!id || isBusy(id)) return false
    setBusy(id, true)
    postStatus(id, "approve", notify)
    return true
  }

  // POST /request/{id}/approve|decline, for an id already marked busy.
  function postStatus(id, action, notify) {
    api("POST", "/request/" + id + "/" + action, null, function(res) {
      root.afterAction(id, action, res, res.ok ? Seerr.normalizeRequest(res.data) : null, notify)
    })
  }

  // Approve or decline from IPC or a notification button. Seerr sets the
  // status it is asked for whatever the current one is, and a notification
  // stays clickable in the history long after it was sent: the request may
  // have been declined (or approved) since, or the URL may now point to
  // another Seerr. So the request is read first and only a pending one, of
  // the server the notification named, is acted on. The outcome is notified.
  function actFromOutside(target, action) {
    var named = Seerr.actionTarget(target)
    var id = named.id
    if (!id) return "ignored"
    if (isBusy(id)) return "busy"
    if (named.origin !== "" && named.origin !== keyOrigin) {
      // Not looked up here: the same id names another request on this server.
      var message = describeError({ error: "otherServer" })
      actionDone(id, action, false, message)
      sendNotification(t("notify.actionFailed").arg("#" + id), message, "", 0, false, "normal")
      return "other server"
    }
    setBusy(id, true)
    fetchRequest(id, function(req, res) {
      if (!req) { root.afterAction(id, action, res.ok ? { ok: false, status: 0, error: "badJson" } : res, null, true); return }
      if (req.status !== Seerr.REQUEST_PENDING) {
        root.afterAction(id, action, { ok: false, status: 0, error: "notPending" }, req, true)
        return
      }
      root.postStatus(id, action, true)
    })
    return "ok"
  }

  // The advanced path: save the chosen server, profile, folder, tags and
  // seasons on the request, then approve it.
  function approveWithForm(req, form) {
    if (!req || isBusy(req.id)) return false
    if (Seerr.formProblem(req, form) !== "") return false
    var id = req.id
    setBusy(id, true)
    api("PUT", "/request/" + id, Seerr.updateBody(req, form), function(res) {
      if (!res.ok) { root.afterAction(id, "approve", res, null, false); return }
      root.api("POST", "/request/" + id + "/approve", null, function(res2) {
        root.afterAction(id, "approve", res2, res2.ok ? Seerr.normalizeRequest(res2.data) : null, false)
      })
    })
    return true
  }

  function decline(id, notify) {
    id = Seerr.positiveId(id)
    if (!id || isBusy(id)) return false
    setBusy(id, true)
    postStatus(id, "decline", notify)
    return true
  }

  function retry(id) {
    id = Seerr.positiveId(id)
    if (!id || isBusy(id)) return false
    setBusy(id, true)
    api("POST", "/request/" + id + "/retry", null, function(res) {
      root.afterAction(id, "retry", res, res.ok ? Seerr.normalizeRequest(res.data) : null, false)
    })
    return true
  }

  function remove(id) {
    id = Seerr.positiveId(id)
    if (!id || isBusy(id)) return false
    setBusy(id, true)
    api("DELETE", "/request/" + id, null, function(res) {
      root.afterAction(id, "delete", res, null, false)
    })
    return true
  }

  // ---------------------------------------------------------------- services

  property var _servers: ({})
  property var _serverDetails: ({})
  readonly property int serviceCacheMs: 5 * 60 * 1000

  function serviceType(req) { return req && req.type === "tv" ? "sonarr" : "radarr" }

  function loadServers(type, cb) {
    var cached = _servers[type]
    if (cached && Date.now() - cached.at < serviceCacheMs) { cb(cached.value, null); return }
    api("GET", "/service/" + type, null, function(res) {
      if (!res.ok) { cb(null, root.describeError(res)); return }
      var value = Seerr.normalizeServers(res.data)
      var next = root._servers
      next[type] = { at: Date.now(), value: value }
      root._servers = next
      cb(value, null)
    })
  }

  function loadServerDetails(type, serverId, cb) {
    var key = type + ":" + serverId
    var cached = _serverDetails[key]
    if (cached && Date.now() - cached.at < serviceCacheMs) { cb(cached.value, null); return }
    api("GET", "/service/" + type + "/" + serverId, null, function(res) {
      if (!res.ok) { cb(null, root.describeError(res)); return }
      var value = Seerr.normalizeServerDetails(res.data)
      var next = root._serverDetails
      next[key] = { at: Date.now(), value: value }
      root._serverDetails = next
      cb(value, null)
    })
  }

  // ---------------------------------------------------------------- notifications

  readonly property string notifySend: omarchyPath + "/bin/omarchy-notification-send"
  readonly property string shellCli: omarchyPath + "/bin/omarchy-shell"
  readonly property string glyph: "\u{f0fce}"

  // omarchy-notification-send reads a leading-dash headline or body as an
  // option; a word joiner keeps text from Seerr from ever looking like one.
  function safeArg(text) {
    var s = String(text || "")
    return s.charAt(0) === "-" ? "⁠" + s : s
  }

  function sendNotification(summary, body, imagePath, requestId, withActions, urgency) {
    var argv = [notifySend, "--app-name", "Seerr", "-g", glyph, "-u", urgency || settings.notifyUrgency]
    if (imagePath) argv.push("--image", imagePath)
    argv.push(safeArg(summary), safeArg(Seerr.neutralizeMarkup(body)))
    // The request, and the server it is on: see actFromOutside.
    var target = String(requestId) + (keyOrigin ? "@" + keyOrigin : "")
    if (withActions && requestId > 0) {
      // The card's own click runs the first action, so the harmless one leads.
      argv.push("--action", t("notify.details"), shellCli, pluginId, "show")
      if (canManage) {
        argv.push("--action", t("notify.approve"), shellCli, pluginId, "approve")
        argv.push("--action", t("notify.decline"), shellCli, pluginId, "decline")
      }
      argv.push("--with", target)
    } else if (requestId > 0) {
      argv.push("--exec", shellCli, pluginId, "show", target)
    } else if (requestId === -1) {
      argv.push("--exec", shellCli, pluginId, "open")
    }
    Quickshell.execDetached(argv)
  }

  function requestLine(req) {
    var parts = []
    if (req.requestedBy) parts.push(t("notify.by").arg(req.requestedBy.name))
    parts.push(req.type === "tv" ? t("type.tv") : t("type.movie"))
    if (req.is4k) parts.push("4K")
    if (req.type === "tv" && req.seasons.length) parts.push(t("detail.seasonsShort").arg(Seerr.seasonsLabel(req.seasons)))
    return parts.join(" · ")
  }

  function announceNew(req) {
    ensureMedia(req, function(m) {
      var summary = t("notify.newRequest").arg(root.titleFor(req))
      root.withPoster(m, function(path) {
        root.sendNotification(summary, root.requestLine(req), path, req.id, true)
      })
    })
  }

  function announceMany(list) {
    sendNotification(tn("notify.newRequests", list.length), t("notify.openPanel"), "", -1, false)
  }

  function announceStatus(req, statusKey) {
    ensureMedia(req, function(m) {
      var summary = (statusKey === "available" ? t("notify.available") : t("notify.failed")).arg(root.titleFor(req))
      root.withPoster(m, function(path) {
        root.sendNotification(summary, root.requestLine(req), path, req.id, false,
          statusKey === "failed" ? "normal" : "low")
      })
    })
  }

  function announceResult(id, action, ok, message, updated) {
    var finish = function(req) {
      var title = req ? root.titleFor(req) : ("#" + id)
      if (ok) {
        var key = action === "approve" ? "notify.approved" : "notify.declined"
        root.sendNotification(root.t(key).arg(title), "", "", req ? req.id : 0, false, "low")
      } else {
        root.sendNotification(root.t("notify.actionFailed").arg(title), message, "", id, false, "normal")
      }
    }
    if (updated) ensureMedia(updated, function() { finish(updated) })
    else fetchRequest(id, function(req) {
      if (req) ensureMedia(req, function() { finish(req) })
      else finish(null)
    })
  }

  // Posters for notifications are cached files: the daemon wants a path.
  property var _posterQueue: []

  function withPoster(m, cb) {
    var url = m && settings.notifyPoster ? Seerr.posterUrl(m.posterPath, "w185") : ""
    if (!url || !dirsReady) { cb(""); return }
    var file = cacheDir + "/posters/" + m.posterPath.slice(1)
    _posterQueue.push({ url: url, file: file, cb: cb })
    if (!posterFetch.running) nextPoster()
  }

  function nextPoster() {
    if (_posterQueue.length === 0) return
    var job = _posterQueue[0]
    posterFetch.job = job
    posterFetch.command = ["bash", "-c",
      "[[ -s $1 ]] && exit 0\n" +
      "tmp=$1.part\n" +
      "curl -sfL --proto =https --max-time 10 --max-filesize 3000000 -o \"$tmp\" -- \"$2\" && mv -f -- \"$tmp\" \"$1\" || { rm -f -- \"$tmp\"; exit 1; }",
      "omaseerr-poster", job.file, job.url]
    posterFetch.running = true
  }

  Process {
    id: posterFetch
    property var job: null
    onExited: function(code) {
      var job = posterFetch.job
      root._posterQueue.shift()
      if (job) job.cb(code === 0 ? job.file : "")
      root.nextPoster()
    }
  }

  // ---------------------------------------------------------------- persistence

  Process {
    id: prepareDirs
    command: ["bash", "-c",
      "umask 077\n" +
      "mkdir -p -- \"$1\" \"$2/posters\" && chmod 700 -- \"$1\" || exit 1\n" +
      "f=$1/state.json\n" +
      "[[ -L $f ]] && rm -f -- \"$f\"\n" +
      "[[ -e $f ]] || : >\"$f\"\n" +
      "find \"$2/posters\" -type f -mtime +30 -delete 2>/dev/null\n" +
      "exit 0",
      "omaseerr-state", root.stateDir, root.cacheDir]
    onExited: function(code) { root.dirsReady = code === 0 }
  }

  FileView {
    id: stateFile
    path: root.dirsReady ? root.stateDir + "/state.json" : ""
    atomicWrites: true
    printErrors: false
    onLoaded: {
      root._state = Seerr.parseState(text())
      root._stateLoaded = true
      root.poll()
    }
    onLoadFailed: {
      root._state = Seerr.parseState("")
      root._stateLoaded = true
    }
  }

  function saveState() {
    // Saving before the file was read would replace what it holds.
    if (!dirsReady || !_stateLoaded) return
    saveTimer.restart()
  }

  Timer {
    id: saveTimer
    interval: 500
    onTriggered: {
      var st = root._state
      stateFile.setText(JSON.stringify({ url: st.url, seen: st.seen, statuses: st.statuses, primed: st.primed }) + "\n")
    }
  }

  // ---------------------------------------------------------------- IPC

  // Opens the panel on the focused monitor; the shell picks which copy.
  function openPanel() {
    if (!shell || typeof shell.summon !== "function") return "no shell"
    return shell.summon(pluginId, "{}") ? "ok" : "not summoned"
  }

  // A request of another server than the one now configured is not shown:
  // its id would open an unrelated request here.
  function showRequest(target) {
    var named = Seerr.actionTarget(target)
    focusRequestId = named.origin === "" || named.origin === keyOrigin ? named.id : 0
    return openPanel()
  }

  function statusLine() {
    if (connection === "connected") return "connected pending=" + counts.pending + " total=" + counts.total
    if (connection === "unconfigured") return !baseUrl ? "unconfigured: no url" : "unconfigured: no api key"
    return connection + (lastError ? ": " + lastError : "")
  }

  ShellIpc {
    target: Seerr.PLUGIN_ID

    function ping(): string { return "ok" }
    function status(): string { return root.statusLine() }
    function pending(): string { return String(root.counts.pending) }
    function refresh(): string { root.refresh(); return "ok" }
    function open(): string { root.focusRequestId = 0; return root.openPanel() }
    function toggle(): string { if (root.shell) root.shell.toggle(root.pluginId, "{}"); return "ok" }
    function show(id: string): string { return root.showRequest(id) }
    function approve(id: string): string { return root.actFromOutside(id, "approve") }
    function decline(id: string): string { return root.actFromOutside(id, "decline") }
    function reloadKey(): string { root.loadKey(); return "ok" }
    // omarchy-shell myouboku.omaseerr set notifyStatusChanges true
    function set(key: string, value: string): string {
      var v = Seerr.parseSettingValue(key, value)
      if (v === undefined) return "invalid"
      var patch = {}
      patch[key] = v
      return root.saveSettings(patch) ? "ok" : "not saved"
    }
    function get(key: string): string {
      return Object.prototype.hasOwnProperty.call(root.settings, key) ? String(root.settings[key]) : "unknown"
    }
  }
}
