import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "model/Seerr.js" as Seerr
import "pages"
import "ui"
import "ui/Glyphs.js" as Glyphs

// The bar icon and its panel. One of these exists per monitor; all state and
// network traffic live in Service.qml, which every copy shares.
Panel {
  id: root
  moduleName: Seerr.PLUGIN_ID
  ipcTarget: Seerr.PLUGIN_ID
  // The service answers IPC once for all monitors.
  manageIpc: false

  // ---------------------------------------------------------------- service

  property var svc: null

  function resolveService() {
    if (svc) return
    var api = bar && bar.shell ? bar.shell : null
    if (api && typeof api.serviceFor === "function") svc = api.serviceFor(Seerr.PLUGIN_ID)
    if (svc) pushSettings()
  }

  // The bar assigns `settings` (our shell.json entry) on load and on every
  // change; the service takes them from here.
  property bool _settingsInjected: false
  onSettingsChanged: {
    _settingsInjected = true
    pushSettings()
  }
  function pushSettings() {
    if (!svc || !_settingsInjected) return
    var copy = {}
    var src = settings || {}
    for (var k in src) copy[k] = src[k]
    svc.widgetSettings = copy
  }
  onBarChanged: resolveService()
  Component.onCompleted: resolveService()
  // The service may finish loading after the widget does.
  Timer {
    interval: 500
    repeat: true
    running: root.svc === null
    onTriggered: root.resolveService()
  }

  function t(key) { return svc ? svc.strings.t(key) : key }
  function tn(key, n) { return svc ? svc.tn(key, n) : String(n) }

  // ---------------------------------------------------------------- theme

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color accent: Commons.Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function statusColor(key) {
    var c = Seerr.statusColor(key)
    if (c === "") return foreground
    if (c === "dim") return dim
    return c
  }

  readonly property var cfg: svc ? svc.settings : Seerr.normalizeSettings({})
  readonly property bool connected: !!svc && svc.connection === "connected"
  readonly property int pending: svc ? svc.counts.pending : 0

  // ---------------------------------------------------------------- navigation

  // "list" | "detail" | "approve" | "settings"
  property string page: "list"
  property int cursor: 0
  property int detailId: 0
  property bool confirmOpen: false
  property string confirmAction: ""
  property int confirmId: 0

  readonly property var visibleRows: {
    if (!svc) return []
    var rev = svc.mediaRevision
    var view = svc.view
    var out = []
    for (var i = 0; i < svc.rows.length; i++) {
      var r = svc.rows[i]
      if (Seerr.matchesView(r, view, svc.mediaFor(r))) out.push(r)
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

  // The panel's content (built when first opened): the pages, the toast and
  // the confirmation dialog.
  readonly property Item content: panel.loadedContent

  // True while the list page's own key handling has the keyboard, not one
  // of its filters or the search field.
  readonly property bool listFocused: page === "list" && !!panel.loadedContent && panel.loadedContent.activeFocus

  function selectedRow() {
    return visibleRows.length ? visibleRows[Math.max(0, Math.min(cursor, visibleRows.length - 1))] : null
  }

  function currentReq() {
    return page === "list" ? selectedRow() : detailReq
  }

  function go(next) {
    page = next
    Qt.callLater(function() { if (panel.loadedContent) panel.loadedContent.forceActiveFocus() })
  }

  function openDetail(req) {
    if (!req) return
    detailId = req.id
    _detailFallback = req
    if (svc) svc.ensureMedia(req, null)
    go("detail")
  }

  function openDetailById(id) {
    if (!svc || !id) return
    var row = svc.rowById(id)
    if (row) { openDetail(row); return }
    detailId = id
    _detailFallback = null
    go("detail")
    svc.fetchRequest(id, function(req) {
      if (req && root.detailId === id) {
        root._detailFallback = req
        root.svc.ensureMedia(req, null)
      }
    })
  }

  function back() {
    if (page === "approve") go(detailId ? "detail" : "list")
    else if (page === "detail" || page === "settings") go("list")
    else close()
  }

  // On the list, moves the cursor. On a request's details, steps to the
  // previous or next request of the list, keeping the cursor on it.
  function moveCursor(dy) {
    if (page === "detail") { stepDetail(dy); return }
    if (page !== "list" || visibleRows.length === 0) return
    cursor = Math.max(0, Math.min(visibleRows.length - 1, cursor + dy))
    scrollCursorIntoView()
    if (dy > 0 && cursor >= visibleRows.length - 3 && svc) svc.loadMore()
  }

  function stepDetail(dy) {
    var at = -1
    for (var i = 0; i < visibleRows.length; i++) if (visibleRows[i].id === detailId) at = i
    if (visibleRows.length === 0) return
    var next
    // Gone from the list (just approved or declined under the pending
    // filter): the next request now sits where it was, at the cursor.
    if (at === -1) next = Math.max(0, Math.min(visibleRows.length - 1, dy > 0 ? cursor + dy - 1 : cursor + dy))
    else next = Math.max(0, Math.min(visibleRows.length - 1, at + dy))
    if (next === at) return
    cursor = next
    openDetail(visibleRows[next])
    if (dy > 0 && next >= visibleRows.length - 3 && svc) svc.loadMore()
  }

  // Keeps the focused control in view when Tab moves to one that is
  // scrolled out of its page.
  function revealFocus(item) {
    if (!item) return
    for (var p = item.parent; p; p = p.parent) {
      if (p.contentItem === undefined || p.contentY === undefined || p.flicking === undefined) continue
      var y = item.mapToItem(p.contentItem, 0, 0).y
      var margin = Style.space(6)
      if (y < p.contentY) p.contentY = Math.max(0, y - margin)
      else if (y + item.height > p.contentY + p.height)
        p.contentY = Math.min(Math.max(0, p.contentHeight - p.height), y + item.height - p.height + margin)
      return
    }
  }

  function scrollCursorIntoView() {
    var content = panel.loadedContent
    if (!content || !content.listFlick || !content.rowRepeater) return
    var flick = content.listFlick
    var item = content.rowRepeater.itemAt(cursor)
    if (!item) return
    Qt.callLater(function() {
      var y = item.y
      var margin = Style.space(6)
      if (y < flick.contentY) flick.contentY = Math.max(0, y - margin)
      else if (y + item.height > flick.contentY + flick.height)
        flick.contentY = Math.min(Math.max(0, flick.contentHeight - flick.height), y + item.height - flick.height + margin)
    })
  }

  // ---------------------------------------------------------------- actions

  // Approve with the form, or straight away with Seerr's defaults when Shift
  // is held (or the caller asks for it).
  function approve(req, quick) {
    if (!svc || !req || req.status !== Seerr.REQUEST_PENDING || !svc.canManage) return
    if (quick) { svc.quickApprove(req.id, false); return }
    startApproveForm(req)
  }

  function decline(req) {
    if (!svc || !req || req.status !== Seerr.REQUEST_PENDING || !svc.canManage) return
    if (cfg.confirmDecline) askConfirm("decline", req.id)
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

  Connections {
    target: root.svc
    ignoreUnknownSignals: true
    function onActionDone(requestId, action, ok, message) {
      if (!ok) { root.flash(message, true); return }
      var key = { approve: "notify.approved", decline: "notify.declined", "delete": "toast.deleted", retry: "toast.retried" }[action]
      if (key) root.flash(root.t(key).arg(message || ("#" + requestId)), false)
      if (action === "approve" && root.page === "approve" && root.detailId === requestId) root.go("detail")
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
  Timer {
    id: flashTimer
    interval: 2600
    onTriggered: root.flashText = ""
  }

  // Seerr stopped answering after it had: what is shown is from before.
  readonly property bool offline: !!svc && (svc.connection === "error" || (svc.connection === "connecting" && svc.lastError !== ""))
  readonly property bool retrying: !!svc && svc.connection === "connecting" && svc.lastError !== ""

  // ---------------------------------------------------------------- approval form

  property var formReq: null
  property var formServers: []
  property var formDetails: null
  property var form: null
  property bool formLoading: false
  property string formError: ""
  readonly property var formMedia: formReq && svc ? (svc.mediaRevision, svc.mediaFor(formReq)) : null

  function startApproveForm(req) {
    formReq = req
    detailId = req.id
    _detailFallback = req
    formServers = []
    formDetails = null
    form = null
    formError = ""
    formLoading = true
    go("approve")
    var type = svc.serviceType(req)
    svc.ensureMedia(req, function(m) {
      svc.loadServers(type, function(servers, error) {
        if (root.formReq !== req) return
        if (error) { root.formLoading = false; root.formError = error; return }
        root.formServers = Seerr.formServers(servers, req)
        var server = Seerr.pickServer(servers, req)
        if (!server) { root.formLoading = false; root.formError = root.t("approve.noServers"); return }
        root.selectServer(server.id, m)
      })
    })
  }

  function selectServer(serverId, m) {
    var req = formReq
    var server = null
    var all = formServers
    for (var i = 0; i < all.length; i++) if (all[i].id === serverId) server = all[i]
    if (!server) { formLoading = false; formError = t("approve.noServers"); return }
    formLoading = true
    formError = ""
    svc.loadServerDetails(svc.serviceType(req), server.id, function(details, error) {
      if (root.formReq !== req) return
      root.formLoading = false
      if (error) { root.formError = error; return }
      var media = m !== undefined ? m : root.formMedia
      var seasons = root.form && root.form.seasons ? root.form.seasons : null
      root.formDetails = details
      var f = Seerr.defaultForm(req, server, details, !!(media && media.anime))
      if (seasons) f.seasons = seasons
      root.form = f
    })
  }

  function setForm(patch) {
    var next = {}
    for (var k in form) next[k] = form[k]
    for (var p in patch) next[p] = patch[p]
    form = next
  }

  function submitForm(quick) {
    if (!formReq || !svc) return
    if (quick) { svc.quickApprove(formReq.id, false); go("detail"); return }
    var problem = Seerr.formProblem(formReq, form)
    if (problem) { flash(t("approve.problem." + problem), true); return }
    svc.approveWithForm(formReq, form)
  }

  // ---------------------------------------------------------------- keyboard

  function handleKey(event) {
    if (confirmOpen) {
      var dialog = panel.loadedContent ? panel.loadedContent.confirm : null
      if (dialog && dialog.handleKey(event)) event.accepted = true
      return
    }
    var shift = (event.modifiers & Qt.ShiftModifier) !== 0
    var key = event.key
    var text = event.text

    if (key === Qt.Key_Escape) {
      var content = panel.loadedContent
      // On the list and the approval form, Escape first leaves a control
      // (search, a dropdown, a chip, a button) for the page's own keys;
      // the next one goes back.
      if (content && !content.activeFocus && (page === "list" || page === "approve")) {
        if (page === "list" && content.searchField && content.searchField.activeFocus && svc && svc.view.search)
          svc.setView({ search: "" })
        content.forceActiveFocus()
      } else back()
      event.accepted = true
      return
    }
    // Typing goes to text fields; only Escape above reaches us from them.
    if (page === "settings" || page === "approve") {
      if (page === "approve" && (key === Qt.Key_Return || key === Qt.Key_Enter)) {
        submitForm(shift)
        event.accepted = true
      }
      return
    }

    var focusedContent = panel.loadedContent
    if (key === Qt.Key_Down && focusedContent && focusedContent.searchField && focusedContent.searchField.activeFocus) {
      focusedContent.forceActiveFocus()
      event.accepted = true
      return
    }
    if (key === Qt.Key_Down || text === "j") { moveCursor(1); event.accepted = true; return }
    if (key === Qt.Key_Up || text === "k") { moveCursor(-1); event.accepted = true; return }
    if (key === Qt.Key_PageDown) { moveCursor(8); event.accepted = true; return }
    if (key === Qt.Key_PageUp) { moveCursor(-8); event.accepted = true; return }
    if (key === Qt.Key_Home) { moveCursor(-visibleRows.length); event.accepted = true; return }
    if (key === Qt.Key_End) { moveCursor(visibleRows.length); event.accepted = true; return }
    if (key === Qt.Key_Backspace || text === "h") {
      if (page === "detail") { back(); event.accepted = true }
      return
    }

    var req = currentReq()
    if (key === Qt.Key_Return || key === Qt.Key_Enter) {
      if (page === "list" && !shift) openDetail(req)
      else approve(req, shift)
      event.accepted = true
      return
    }
    if (text === "a") { approve(req, false); event.accepted = true; return }
    if (text === "A") { approve(req, true); event.accepted = true; return }
    if (text === "d" || text === "D") { decline(req); event.accepted = true; return }
    if (key === Qt.Key_Delete || text === "x") { remove(req); event.accepted = true; return }
    if (text === "R" && req && req.status === Seerr.REQUEST_FAILED) { svc.retry(req.id); event.accepted = true; return }
    if (text === "o") { if (svc) svc.openInBrowser(req); event.accepted = true; return }
    if (text === "r") { if (svc) svc.refresh(); event.accepted = true; return }
    if (text === "s") { go("settings"); event.accepted = true; return }
    if (page === "list") {
      if (text === "/") {
        var c = panel.loadedContent
        if (c && c.searchField) c.searchField.forceActiveFocus()
        event.accepted = true
        return
      }
      if (text === "f" || text === "F") { cycleView("filter", Seerr.FILTERS, text === "F"); event.accepted = true; return }
      if (text === "t") { cycleView("mediaType", Seerr.MEDIA_TYPES, shift); event.accepted = true; return }
      if (text === "S") { cycleView("sort", Seerr.SORTS, false); event.accepted = true; return }
      if (text === "i") { cycleView("sortDirection", Seerr.DIRECTIONS, false); event.accepted = true; return }
    }
  }

  function saveSetting(patch) {
    if (!svc || !svc.saveSettings(patch)) flash(t("settings.saveFailed"), true)
  }

  function cycleView(key, values, backwards) {
    if (!svc) return
    var at = values.indexOf(svc.view[key])
    var next = values[(at + (backwards ? values.length - 1 : 1)) % values.length]
    var patch = {}
    patch[key] = next
    cursor = 0
    svc.setView(patch)
  }

  // ---------------------------------------------------------------- lifecycle

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    if (!svc) return
    if (opened) {
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
      Qt.callLater(function() { if (panel.loadedContent) panel.loadedContent.forceActiveFocus() })
    } else {
      svc.openPanels = Math.max(0, svc.openPanels - 1)
    }
  }

  // A notification's "Details" while the panel is already open.
  Connections {
    target: root.svc
    ignoreUnknownSignals: true
    function onFocusRequestIdChanged() {
      if (root.opened && root.svc.focusRequestId > 0) {
        var id = root.svc.focusRequestId
        root.svc.focusRequestId = 0
        root.openDetailById(id)
      }
    }
    function onRowsChanged() {
      if (root.cursor >= root.visibleRows.length) root.cursor = Math.max(0, root.visibleRows.length - 1)
    }
  }

  // Relative times ("5 min ago") move on while the panel is open.
  property double now: Date.now()
  Timer {
    interval: 30000
    repeat: true
    running: root.opened
    onTriggered: root.now = Date.now()
  }

  // ---------------------------------------------------------------- bar icon

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: {
      var state
      if (!root.svc) state = "Seerr"
      else if (root.svc.connection === "connected") state = root.tn("bar.pending", root.pending)
      else if (root.svc.connection === "unconfigured") state = root.t("bar.setup")
      else if (root.svc.connection === "connecting") state = root.t("bar.connecting")
      else state = root.t("bar.error") + "\n" + root.svc.lastError
      return state + "\n" + root.t("bar.clicks")
    }
    // The kit draws and optically centres the glyph. Accent while requests
    // wait; a warning sign in red when Seerr is unreachable, so it does not
    // hang on telling two colours apart; dimmed while not set up or
    // connecting.
    text: root.svc && root.svc.connection === "error" ? Glyphs.warning : Glyphs.seerr
    foreground: {
      if (!root.svc || root.svc.connection === "unconfigured" || root.svc.connection === "connecting")
        return Qt.darker(root.barForeground, 1.55)
      if (root.svc.connection === "error") return root.urgent
      return root.pending > 0 ? root.accent : root.barForeground
    }
    // A short bump when new requests come in.
    SequentialAnimation {
      id: barPulse
      NumberAnimation { target: button; property: "scale"; to: 1.3; duration: Style.duration(140); easing.type: Easing.OutCubic }
      NumberAnimation { target: button; property: "scale"; to: 1; duration: Style.duration(260); easing.type: Easing.OutBack }
    }
    property int lastPending: -1
    Connections {
      target: root
      function onPendingChanged() {
        if (button.lastPending >= 0 && root.pending > button.lastPending) barPulse.restart()
        button.lastPending = root.pending
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) { if (root.svc) root.svc.refresh() }
      else if (buttonCode === Qt.MiddleButton) { if (root.svc) root.svc.openInBrowser(null) }
      else root.toggle()
    }
  }

  // ---------------------------------------------------------------- panel

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(640))

    content: Item {
      id: body
      readonly property var listFlick: listPage.flick
      readonly property var rowRepeater: listPage.rowRepeater
      readonly property var searchField: listPage.searchField
      readonly property var confirm: confirmDialog
      anchors.fill: parent
      focus: true
      implicitHeight: {
        if (root.page === "detail") return detailPage.implicitHeight
        if (root.page === "approve") return approvePage.implicitHeight
        if (root.page === "settings") return settingsPage.implicitHeight
        return listPage.implicitHeight
      }
      // On the list, Tab comes back here after the filters and the search.
      activeFocusOnTab: root.page === "list"
      Keys.onPressed: function(event) { root.handleKey(event) }
      readonly property Item focusedItem: Window.activeFocusItem
      onFocusedItemChanged: Qt.callLater(function() { root.revealFocus(body.focusedItem) })

      ListPage { id: listPage; ctx: root; anchors.fill: parent; visible: root.page === "list"; FadeIn on opacity {} }
      DetailPage { id: detailPage; ctx: root; anchors.fill: parent; visible: root.page === "detail"; FadeIn on opacity {} }
      ApprovePage { id: approvePage; ctx: root; anchors.fill: parent; visible: root.page === "approve"; FadeIn on opacity {} }
      SettingsPage { id: settingsPage; ctx: root; anchors.fill: parent; visible: root.page === "settings"; FadeIn on opacity {} }

      Toast {
        z: 5
        message: root.flashText
        isError: root.flashError
        serial: root.flashSerial
        foreground: root.foreground
        success: root.statusColor("available")
        urgent: root.urgent
        fontFamily: root.fontFamily
      }

      ConfirmDialog {
        id: confirmDialog
        anchors.fill: parent
        z: 10
        opened: root.confirmOpen
        // Each question starts on its action, whatever was picked last time.
        onOpenedChanged: if (opened) selectedIndex = 1
        message: root.confirmAction === "delete" ? root.t("confirm.delete") : root.t("confirm.decline")
        confirmText: root.confirmAction === "delete" ? root.t("action.delete") : root.t("action.decline")
        cancelText: root.t("action.cancel")
        foreground: root.foreground
        fontFamily: root.fontFamily
        onCanceled: root.confirmOpen = false
        onConfirmed: root.confirmYes()
      }
    }
  }

  // ================================================================ dates

  // "3 h ago · 9 Nov 18:55": how long ago first, the date for reference.
  function longDate(ms) {
    if (!ms) return ""
    return relative(ms) + " · " + shortDateTime(ms)
  }

  function shortDateTime(ms) {
    if (!ms) return ""
    var d = new Date(ms)
    var loc = Qt.locale(Commons.I18n.formatLocale)
    var sameYear = d.getFullYear() === new Date().getFullYear()
    return d.toLocaleDateString(loc, sameYear ? "d MMM" : "d MMM yyyy") + " " + d.toLocaleTimeString(loc, Locale.ShortFormat)
  }

  // Compact age for the list: "3 h", "20 min", "2 d".
  function age(ms) {
    return Seerr.relativeTime(ms, Math.max(now, Date.now() - 1000), {
      now: t("age.now"),
      minutes: function(n) { return t("age.minutes").arg(n) },
      hours: function(n) { return t("age.hours").arg(n) },
      days: function(n) { return t("age.days").arg(n) },
      date: function(v) { return new Date(v).toLocaleDateString(Qt.locale(Commons.I18n.formatLocale), "d MMM yyyy") }
    })
  }

  function relative(ms) {
    return Seerr.relativeTime(ms, Math.max(now, Date.now() - 1000), {
      now: t("time.now"),
      minutes: function(n) { return tn("time.minutes", n) },
      hours: function(n) { return tn("time.hours", n) },
      days: function(n) { return tn("time.days", n) },
      date: function(v) { return new Date(v).toLocaleDateString(Qt.locale(Commons.I18n.formatLocale), Locale.ShortFormat) }
    })
  }
}
