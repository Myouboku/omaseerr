import QtQuick
import qs.Commons as Commons
import "../model/api.js" as Api
import "../model/requests.js" as Requests

// The requests the panels show: the list (view, rows, paging), the latest
// version of every request seen, and the tmdb details (titles, posters) of
// their media.
QtObject {
  id: store
  // The service: settings, open panels, translations.
  required property var svc
  required property var http
  // Whether Seerr is reachable, and how to put its errors in words.
  required property var conn

  // The panel's list.
  property var view: ({
    filter: svc.settings.defaultFilter,
    mediaType: svc.settings.defaultMediaType,
    sort: svc.settings.defaultSort,
    sortDirection: svc.settings.defaultSortDirection,
    search: ""
  })
  property var rows: []
  property int rowsTotal: 0
  property bool listLoading: false
  property string listError: ""
  property int _listSkip: 0
  property int _listGeneration: 0
  readonly property bool hasMore: _listSkip < rowsTotal

  // tmdb details by Api.mediaKey; mediaRevision bumps on every arrival so
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

  // A new connection: no list load is waited for any more.
  // A new connection to the same server (a retry): the calls under way were
  // dropped and will never answer. Whoever waited on a title gets none now
  // (a notification still goes out, with the fallback title) instead of
  // waiting for good, and the next ensureMedia asks again.
  function stopLoading() {
    listLoading = false
    var waiting = _mediaWaiters
    _mediaWaiters = ({})
    for (var key in waiting)
      for (var i = 0; i < waiting[key].length; i++) waiting[key][i](null)
  }

  // Another server, or none: nothing of the previous one stays.
  function clear() {
    _known = ({})
    knownRevision++
    rows = []
    rowsTotal = 0
    _listSkip = 0
    media = ({})
    mediaRevision++
    // The calls these waited on were just dropped and will never answer;
    // left in place, they would keep their media from ever loading again.
    _mediaWaiters = ({})
  }

  // A language switch changes the titles Seerr hands back.
  property Connections _language: Connections {
    target: Commons.I18n
    function onLanguageChanged() {
      store.media = ({})
      store.mediaRevision++
      if (store.svc.openPanels > 0) store.reloadList()
    }
  }

  // A change to the default filter or sort resets the list to it.
  property string _defaultsKey: ""
  property Connections _settings: Connections {
    target: store.svc
    function onSettingsChanged() {
      var settings = store.svc.settings
      var key = [settings.defaultFilter, settings.defaultMediaType, settings.defaultSort, settings.defaultSortDirection].join("|")
      if (store._defaultsKey !== "" && key !== store._defaultsKey) {
        store.resetView()
        if (store.svc.openPanels > 0) store.reloadList()
      }
      store._defaultsKey = key
    }
  }

  function resetView() {
    view = {
      filter: svc.settings.defaultFilter,
      mediaType: svc.settings.defaultMediaType,
      sort: svc.settings.defaultSort,
      sortDirection: svc.settings.defaultSortDirection,
      search: ""
    }
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
    return view.filter === "declined" ? 100 : svc.settings.pageSize
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
    if (listLoading || conn.state !== "connected") return
    var generation = ++_listGeneration
    var take = Math.min(100, Math.max(pageSize(), rows.length))
    http.api("GET", Api.listPath({ filter: view.filter, mediaType: view.mediaType, sort: view.sort, sortDirection: view.sortDirection, take: take, skip: 0 }), null, function(res) {
      if (generation !== store._listGeneration || !res.ok) return
      var page = Api.normalizeRequestList(res.data)
      store.remember(page.requests)
      if (store.rows.length > take) {
        store.rows = Requests.mergePage(page.requests, store.rows.slice(take))
      } else {
        store.rows = page.requests
        store._listSkip = page.requests.length
      }
      store.rowsTotal = page.total
      store.fetchMediaFor(page.requests)
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
    for (var i = 0; i < rows.length; i++) if (rows[i].status === Requests.REQUEST_DECLINED) found++
    if (found < svc.settings.pageSize) Qt.callLater(loadMore)
  }

  function fetchPage(reset) {
    if (conn.state !== "connected") { if (reset) rows = []; return }
    var generation = _listGeneration
    var skip = reset ? 0 : _listSkip
    listLoading = true
    http.api("GET", Api.listPath({ filter: view.filter, mediaType: view.mediaType, sort: view.sort, sortDirection: view.sortDirection, take: pageSize(), skip: skip }), null, function(res) {
      if (generation !== store._listGeneration) return
      store.listLoading = false
      if (!res.ok) { store.listError = store.conn.describeError(res); return }
      var page = Api.normalizeRequestList(res.data)
      store.remember(page.requests)
      store.rows = reset ? page.requests : Requests.mergePage(store.rows, page.requests)
      store.rowsTotal = page.total
      store._listSkip = skip + page.requests.length
      store.listError = ""
      store.fetchMediaFor(page.requests)
      store.continueDeclinedScan()
    })
  }

  function rowById(id) {
    for (var i = 0; i < rows.length; i++) if (rows[i].id === id) return rows[i]
    return null
  }

  function updateRow(req) {
    var found = false
    for (var i = 0; i < rows.length; i++) if (rows[i].id === req.id) found = true
    if (found) rows = Requests.replaceRequest(rows, req)
  }

  function removeRow(id) {
    rows = Requests.removeRequest(rows, id)
  }

  // Fetches one request (for IPC/notification paths that may not have it).
  function fetchRequest(id, cb) {
    http.api("GET", "/request/" + id, null, function(res) {
      var req = res.ok ? Api.normalizeRequest(res.data) : null
      if (req) store.remember([req])
      cb(req, res)
    })
  }

  // ---------------------------------------------------------------- media

  function mediaFor(req) {
    // Reading mediaRevision makes callers' bindings follow new arrivals.
    if (mediaRevision < 0 || !req) return null
    return media[Api.mediaKey(req.type, req.tmdbId)] || null
  }

  function fetchMediaFor(list) {
    for (var i = 0; i < list.length; i++) ensureMedia(list[i], null)
  }

  // `force` fetches even when the cache has it (see refreshMedia).
  function ensureMedia(req, cb, force) {
    if (!req || !req.tmdbId) { if (cb) cb(null); return }
    var key = Api.mediaKey(req.type, req.tmdbId)
    if (media[key] && !force) { if (cb) cb(media[key]); return }
    var waiting = _mediaWaiters[key]
    if (waiting) { if (cb) waiting.push(cb); return }
    _mediaWaiters[key] = cb ? [cb] : []
    var lang = String(Commons.I18n.language || "en")
    http.api("GET", Api.mediaPath(req.type, req.tmdbId) + "?language=" + encodeURIComponent(lang), null, function(res) {
      var waiters = store._mediaWaiters[key] || []
      delete store._mediaWaiters[key]
      var value = res.ok ? Api.normalizeMedia(res.data, req.type) : null
      if (value) {
        var next = store.media
        next[key] = value
        store.media = next
        store.mediaRevision++
      }
      for (var i = 0; i < waiters.length; i++) waiters[i](value)
    })
  }

  // Fetches a media's details again (downloads progress, seasons become
  // available). What the cache holds stays shown until the answer, and
  // stays if the fetch fails. Skipped while a fetch of it is under way.
  function refreshMedia(req) {
    if (!req || !req.tmdbId) return
    if (_mediaWaiters[Api.mediaKey(req.type, req.tmdbId)]) return
    ensureMedia(req, null, true)
  }

  // The title alone and its year, for layouts that keep the year when the
  // title has to be cut.
  function nameFor(req) {
    var m = mediaFor(req)
    if (m && m.title) return m.title
    return req ? (req.type === "tv" ? svc.t("type.tv") : svc.t("type.movie")) + " #" + req.tmdbId : ""
  }
  function yearFor(req) {
    var m = mediaFor(req)
    return m && m.title && m.year ? String(m.year) : ""
  }

  function titleFor(req) {
    var m = mediaFor(req)
    if (m && m.title) return m.year ? m.title + " (" + m.year + ")" : m.title
    return req ? (req.type === "tv" ? svc.t("type.tv") : svc.t("type.movie")) + " #" + req.tmdbId : ""
  }
}
