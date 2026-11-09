import QtQuick
import qs.Commons
import qs.Commons as Commons
import "../model/cursor.js" as Cursor
import "../model/requests.js" as Requests
import "../model/time.js" as Time

// What one panel shows and does: the page, the list's cursor, the request
// on display, the toast, the confirmation question, and the actions behind
// the keys and buttons. One per panel (so per monitor); what they share
// lives in Service.qml.
QtObject {
  id: nav
  // The panel: service, settings, translations, content.
  required property var ctx
  readonly property var svc: ctx.svc

  // ---------------------------------------------------------------- navigation

  // "list" | "detail" | "approve" | "settings"
  property string page: "list"
  property int cursor: 0
  property int detailId: 0
  // The request on display was opened from the list, at the cursor (not
  // from a notification): see Cursor.stepTarget.
  property bool detailFromCursor: false
  property bool confirmOpen: false
  property string confirmAction: ""
  property int confirmId: 0

  readonly property var visibleRows: {
    if (!svc) return []
    var view = svc.view
    // Titles only matter to a search: reading the media otherwise (mediaFor
    // follows every arrival) would rebuild every row for each poster.
    var searching = String(view.search || "").trim() !== ""
    var out = []
    for (var i = 0; i < svc.rows.length; i++) {
      var r = svc.rows[i]
      if (Requests.matchesView(r, view, searching ? svc.mediaFor(r) : null)) out.push(r)
    }
    return out
  }
  readonly property var detailReq: {
    if (!svc || !detailId) return null
    var known = (svc.knownRevision, svc.requestById(detailId))
    if (known) return known
    return _detailFallback && _detailFallback.id === detailId ? _detailFallback : null
  }
  property var _detailFallback: null

  // True while the list page's own key handling has the keyboard, not one
  // of its filters or the search field.
  readonly property bool listFocused: page === "list" && !!ctx.content && ctx.content.activeFocus

  function selectedRow() {
    return visibleRows.length ? visibleRows[Cursor.clampIndex(cursor, visibleRows.length)] : null
  }

  function currentReq() {
    return page === "list" ? selectedRow() : detailReq
  }

  function go(next) {
    page = next
    Qt.callLater(function() { if (nav.ctx.content) nav.ctx.content.forceActiveFocus() })
  }

  // The request the detail and approval pages show, kept even when it is not
  // (or no longer) among the loaded rows.
  function showRequest(req) {
    detailId = req.id
    _detailFallback = req
  }

  function openDetail(req) {
    if (!req) return
    var at = -1
    for (var i = 0; i < visibleRows.length; i++) if (visibleRows[i].id === req.id) at = i
    if (at !== -1) cursor = at
    detailFromCursor = at !== -1
    showRequest(req)
    if (svc) svc.ensureMedia(req, null)
    go("detail")
  }

  function openDetailById(id) {
    if (!svc || !id) return
    var row = svc.rowById(id)
    if (row) { openDetail(row); return }
    detailId = id
    detailFromCursor = false
    _detailFallback = null
    go("detail")
    svc.fetchRequest(id, function(req, res) {
      if (nav.detailId !== id) return
      if (req) {
        nav._detailFallback = req
        nav.svc.ensureMedia(req, null)
        return
      }
      // Deleted since, or Seerr did not answer: say so rather than stay on
      // "Loading…".
      nav.flash(res && res.status === 404 ? nav.ctx.t("detail.gone") : nav.svc.describeError(res), true)
      if (nav.page === "detail") nav.go("list")
    })
  }

  function back() {
    if (page === "approve") go(detailId ? "detail" : "list")
    else if (page === "detail" || page === "settings") go("list")
    else ctx.close()
  }

  // On the list, moves the cursor. On a request's details, steps to the
  // previous or next request of the list, keeping the cursor on it.
  function moveCursor(dy) {
    if (page === "detail") { stepDetail(dy); return }
    if (page !== "list" || visibleRows.length === 0) return
    cursor = Cursor.clampIndex(cursor + dy, visibleRows.length)
    scrollCursorIntoView()
    if (Cursor.wantsMore(dy, cursor, visibleRows.length) && svc) svc.loadMore()
  }

  // From a request's details to another one of the list (the cursor
  // follows), also when the one on display just left the list.
  function stepDetail(dy) {
    var next = Cursor.stepTarget(visibleRows, detailId, cursor, dy, detailFromCursor)
    if (next < 0) return
    cursor = next
    openDetail(visibleRows[next])
    if (Cursor.wantsMore(dy, next, visibleRows.length) && svc) svc.loadMore()
  }

  // Keeps the focused control in view when Tab moves to one that is
  // scrolled out of its page.
  function revealFocus(item) {
    if (!item) return
    for (var p = item.parent; p; p = p.parent) {
      if (p.contentItem === undefined || p.contentY === undefined || p.flicking === undefined) continue
      var y = item.mapToItem(p.contentItem, 0, 0).y
      var to = Cursor.scrollToShow(p.contentY, p.height, p.contentHeight, y, item.height, Style.space(6))
      if (to !== p.contentY) p.contentY = to
      return
    }
  }

  function scrollCursorIntoView() {
    var content = ctx.content
    if (!content || !content.listFlick || !content.rowRepeater) return
    var flick = content.listFlick
    var item = content.rowRepeater.itemAt(cursor)
    if (!item) return
    Qt.callLater(function() {
      var to = Cursor.scrollToShow(flick.contentY, flick.height, flick.contentHeight, item.y, item.height, Style.space(6))
      if (to !== flick.contentY) flick.contentY = to
    })
  }

  // Home / End: the first or last row, or on a request's details the first
  // or last request.
  function moveTo(to) {
    if (visibleRows.length === 0) return
    var target = Cursor.endIndex(to, visibleRows.length)
    if (page === "detail") { stepDetail(target - cursor); return }
    if (page !== "list") return
    moveCursor(target - cursor)
  }

  function cycleView(key, values, backwards) {
    if (!svc) return
    var patch = {}
    patch[key] = Requests.nextValue(values, svc.view[key], backwards)
    cursor = 0
    svc.setView(patch)
  }

  // ---------------------------------------------------------------- actions

  // Approve with the form, or straight away with Seerr's defaults when Shift
  // is held (or the caller asks for it).
  function approve(req, quick) {
    if (!svc || !req || req.status !== Requests.REQUEST_PENDING || !svc.canManage) return
    if (quick) { svc.quickApprove(req.id, false); return }
    ctx.approval.start(req)
  }

  function decline(req) {
    if (!svc || !req || req.status !== Requests.REQUEST_PENDING || !svc.canManage) return
    if (ctx.cfg.confirmDecline) askConfirm("decline", req.id)
    else svc.decline(req.id, false)
  }

  function remove(req) {
    if (!svc || !req) return
    askConfirm("delete", req.id)
  }

  function askConfirm(action, id) {
    confirmAction = action
    confirmId = id
    confirmOpen = true
  }

  function confirmYes() {
    confirmOpen = false
    if (!svc) return
    if (confirmAction === "decline") svc.decline(confirmId, false)
    else if (confirmAction === "delete") {
      svc.remove(confirmId)
      if (page !== "list" && detailId === confirmId) go("list")
    }
  }

  function saveSetting(patch) {
    if (!svc || !svc.saveSettings(patch)) flash(ctx.t("settings.saveFailed"), true)
  }

  property Connections _actions: Connections {
    target: nav.svc
    ignoreUnknownSignals: true
    function onActionDone(requestId, action, ok, message) {
      if (!ok) { nav.flash(message, true); return }
      var key = { approve: "notify.approved", decline: "notify.declined", "delete": "toast.deleted", retry: "toast.retried" }[action]
      if (key) nav.flash(nav.ctx.t(key).arg(message || ("#" + requestId)), false)
      if (action === "approve" && nav.page === "approve" && nav.detailId === requestId) nav.go("detail")
    }
  }

  // A toast at the bottom of the panel for results and errors. Errors stay
  // longer: they usually have something to read.
  property string flashText: ""
  property bool flashError: false
  property int flashSerial: 0
  function flash(text, error) {
    text = String(text || "")
    if (text === "") return
    flashText = text
    flashError = !!error
    flashSerial++
    flashTimer.interval = error ? 6000 : 2600
    flashTimer.restart()
  }
  property Timer _flashTimer: Timer {
    id: flashTimer
    interval: 2600
    onTriggered: nav.flashText = ""
  }

  // ---------------------------------------------------------------- lifecycle

  // Opening starts on the list, or on the request a notification asked
  // for, or on the settings while there is nothing to connect with.
  function opening() {
    if (!svc) return
    svc.openPanels++
    confirmOpen = false
    now = Date.now()
    if (svc.focusRequestId > 0) {
      var id = svc.focusRequestId
      svc.focusRequestId = 0
      openDetailById(id)
    } else {
      page = "list"
      cursor = 0
    }
    if (svc.connection === "connected") svc.reloadList()
    else if (svc.keyState !== "ok" || !svc.baseUrl) page = "settings"
    Qt.callLater(function() { if (nav.ctx.content) nav.ctx.content.forceActiveFocus() })
  }

  function closing() {
    if (!svc) return
    svc.openPanels = Math.max(0, svc.openPanels - 1)
  }

  // A notification's "Details" while the panel is already open.
  property Connections _service: Connections {
    target: nav.svc
    ignoreUnknownSignals: true
    function onFocusRequestIdChanged() {
      if (nav.ctx.opened && nav.svc.focusRequestId > 0) {
        var id = nav.svc.focusRequestId
        nav.svc.focusRequestId = 0
        nav.openDetailById(id)
      }
    }
    // Calls that were under way when Seerr went down are dropped on the
    // retry: once it answers again, a detail page still waiting for its
    // request asks again.
    function onConnectionChanged() {
      if (nav.svc.connection === "connected" && nav.page === "detail" && nav.detailId && !nav.detailReq)
        nav.openDetailById(nav.detailId)
    }
    function onRowsChanged() {
      if (nav.cursor >= nav.visibleRows.length) nav.cursor = Cursor.clampIndex(nav.cursor, nav.visibleRows.length)
    }
  }

  // ---------------------------------------------------------------- dates

  // Relative times ("5 min ago") move on while the panel is open.
  property double now: Date.now()
  property Timer _clock: Timer {
    interval: 30000
    repeat: true
    running: nav.ctx.opened
    onTriggered: nav.now = Date.now()
  }

  // "3 h ago · 9 Nov 18:55": how long ago first, the date for reference.
  function longDate(ms) {
    if (!ms) return ""
    return relative(ms) + " · " + shortDateTime(ms)
  }

  function shortDateTime(ms) {
    if (!ms) return ""
    var d = new Date(ms)
    var loc = Qt.locale(Commons.I18n.formatLocale)
    return d.toLocaleDateString(loc, Time.shortDatePattern(ms, Date.now())) + " " + d.toLocaleTimeString(loc, Locale.ShortFormat)
  }

  // Compact age for the list: "3 h", "20 min", "2 d".
  function age(ms) {
    return Time.relativeTime(ms, Math.max(now, Date.now() - 1000), {
      now: ctx.t("age.now"),
      minutes: function(n) { return nav.ctx.t("age.minutes").arg(n) },
      hours: function(n) { return nav.ctx.t("age.hours").arg(n) },
      days: function(n) { return nav.ctx.t("age.days").arg(n) },
      date: function(v) { return new Date(v).toLocaleDateString(Qt.locale(Commons.I18n.formatLocale), Time.shortDatePattern(v, Date.now())) }
    })
  }

  function relative(ms) {
    return Time.relativeTime(ms, Math.max(now, Date.now() - 1000), {
      now: ctx.t("time.now"),
      minutes: function(n) { return nav.ctx.tn("time.minutes", n) },
      hours: function(n) { return nav.ctx.tn("time.hours", n) },
      days: function(n) { return nav.ctx.tn("time.days", n) },
      date: function(v) { return new Date(v).toLocaleDateString(Qt.locale(Commons.I18n.formatLocale), Locale.ShortFormat) }
    })
  }
}
