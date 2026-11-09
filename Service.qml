import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import "model/Seerr.js" as Seerr
import "service"

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
  // When Seerr last answered, so an outage can say since when.
  property double lastOkAt: 0
  property var me: null
  property bool canManage: true
  property var counts: Seerr.normalizeCounts(null)
  readonly property int pendingCount: counts.pending

  // "loading" | "missing" | "ok" | "error"
  readonly property alias keyState: keyring.state
  readonly property alias keyMessage: keyring.message

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

  readonly property alias stateDir: stateFile.stateDir
  readonly property alias cacheDir: stateFile.cacheDir
  readonly property alias dirsReady: stateFile.dirsReady

  signal actionDone(int requestId, string action, bool ok, string message)

  // ---------------------------------------------------------------- lifecycle

  Component.onCompleted: {
    stateFile.prepare()
    keyring.load()
  }

  onBaseUrlChanged: reconnect()
  // Another server: its key, or none, never the previous one's.
  onKeyOriginChanged: keyring.load()

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

  // `retry` is a new attempt at the same server after an error: what was
  // already shown stays (greyed by the panel) instead of going blank.
  function reconnect(retry) {
    http.reset()
    _polling = false
    listLoading = false
    busy = ({})
    if (retry === true && connection === "error" && keyring.matches(baseUrl)) {
      connection = "connecting"
      api("GET", "/auth/me", null, root.onAuthAnswer)
      return
    }
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
    if (!keyring.matches(baseUrl)) {
      connection = "unconfigured"
      lastError = ""
      return
    }
    connection = "connecting"
    lastError = ""
    lastOkAt = 0
    api("GET", "/auth/me", null, root.onAuthAnswer)
  }

  function onAuthAnswer(res) {
    if (!res.ok) { fail(res); return }
    me = Seerr.normalizeUser(res.data)
    var perms = res.data && typeof res.data.permissions === "number" ? res.data.permissions : 0
    // ADMIN (2) or MANAGE_REQUESTS (16).
    canManage = (perms & 2) !== 0 || (perms & 16) !== 0
    connection = "connected"
    lastError = ""
    lastOkAt = Date.now()
    poll()
    if (openPanels > 0) reloadList()
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

  // ---------------------------------------------------------------- modules

  Keyring {
    id: keyring
    svc: root
    onLoaded: root.reconnect()
  }

  Http {
    id: http
    svc: root
    keyring: keyring
  }

  StateFile {
    id: stateFile
    onRead: root.poll()
  }

  Notifier {
    id: notifier
    svc: root
    store: root
    canManage: root.canManage
    posterDir: stateFile.cacheDir + "/posters"
    postersReady: stateFile.dirsReady
  }

  function api(method, path, body, cb) { http.api(method, path, body, cb) }
  function storeKey(key) { return keyring.store(key) }
  function clearKey() { keyring.clear() }
  function loadKey() { keyring.load() }

  // ---------------------------------------------------------------- polling

  Timer {
    id: pollTimer
    interval: root.settings.refreshIntervalSec * 1000
    repeat: true
    running: root.connection === "connected" || root.connection === "error"
    onTriggered: {
      if (root.connection === "error") root.reconnect(true)
      else root.poll()
    }
  }

  property bool _polling: false

  function refresh() {
    if (connection !== "connected") { reconnect(true); return }
    poll()
    if (openPanels > 0) reloadList()
  }

  function poll() {
    if (connection !== "connected" || _polling) return
    _polling = true
    api("GET", "/request/count", null, function(res) {
      if (!res.ok) { root._polling = false; root.fail(res); return }
      root.counts = Seerr.normalizeCounts(res.data)
      root.lastOkAt = Date.now()
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
      if (root.settings.notifyStatusChanges && stateFile.loaded) root.pollStatuses()
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
      var changes = Seerr.statusChanges(stateFile.state.statuses, recent)
      var next = Seerr.statusMap(recent)
      var st = stateFile.state
      stateFile.state = { url: st.url, seen: st.seen, statuses: next, primed: st.primed }
      stateFile.save()
      if (st.primed) {
        for (var i = 0; i < changes.length; i++) {
          var req = null
          for (var j = 0; j < recent.length; j++) if (recent[j].id === changes[i].id) req = recent[j]
          if (req) notifier.announceStatus(req, changes[i].to)
        }
      }
      if (root.openPanels > 0) root.refreshListQuietly()
    })
  }

  function handlePending(pending) {
    if (!stateFile.loaded) return
    var st = stateFile.state
    var firstRun = !st.primed || st.url !== baseUrl
    var fresh = Seerr.newRequestIds(firstRun ? [] : st.seen, pending)
    var seen = Seerr.rememberIds(firstRun ? [] : st.seen, pending.map(function(r) { return r.id }))
    stateFile.state = { url: baseUrl, seen: seen, statuses: firstRun ? Seerr.statusMap(pending) : st.statuses, primed: true }
    stateFile.save()
    // Requests already pending on a first connection to a server were not
    // missed: they are only recorded as seen.
    if (firstRun) return
    var announce = pending.filter(function(r) { return fresh.indexOf(r.id) !== -1 })
    if (announce.length === 0) return
    notifier.announceArrivals(announce)
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

  // The title alone and its year, for layouts that keep the year when the
  // title has to be cut.
  function nameFor(req) {
    var m = mediaFor(req)
    if (m && m.title) return m.title
    return req ? (req.type === "tv" ? t("type.tv") : t("type.movie")) + " #" + req.tmdbId : ""
  }
  function yearFor(req) {
    var m = mediaFor(req)
    return m && m.title && m.year ? String(m.year) : ""
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

  // actionDone carries the error on failure and the request's title on
  // success, read before a deleted request is forgotten.
  function afterAction(id, action, res, updated, notify) {
    setBusy(id, false)
    var ok = res.ok
    var message = ok ? "" : describeError(res)
    var known = requestById(id) || updated
    var title = known ? titleFor(known) : ""
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
    actionDone(id, action, ok, ok ? title : message)
    if (notify) notifier.announceResult(id, action, ok, message, updated)
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
      notifier.sendNotification(t("notify.actionFailed").arg("#" + id), message, "", 0, false, "normal")
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
