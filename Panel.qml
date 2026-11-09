import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "model/Seerr.js" as Seerr
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

      ListPage { id: listPage; anchors.fill: parent; visible: root.page === "list"; FadeIn on opacity {} }
      DetailPage { id: detailPage; anchors.fill: parent; visible: root.page === "detail"; FadeIn on opacity {} }
      ApprovePage { id: approvePage; anchors.fill: parent; visible: root.page === "approve"; FadeIn on opacity {} }
      SettingsPage { id: settingsPage; anchors.fill: parent; visible: root.page === "settings"; FadeIn on opacity {} }

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

  // ================================================================ pages

  component ListPage: Item {
    id: listRoot
    property alias flick: flick
    property alias rowRepeater: rowRepeater
    property alias searchField: search
    implicitHeight: header.implicitHeight + Style.space(10) + Math.max(Style.space(60), flick.contentHeight)
                    + (listKeys.visible ? listKeys.topMargin + listKeys.implicitHeight : 0)

    // The line under a request's title: type, seasons, who asked, and when.
    function rowDetails(r) {
      if (!r) return ""
      var parts = [(r.type === "tv" ? Glyphs.tv + " " + root.t("type.tv") : Glyphs.movie + " " + root.t("type.movie"))]
      if (r.type === "tv" && r.seasons.length) parts.push(root.t("detail.seasonsShort").arg(Seerr.seasonsLabel(r.seasons)))
      if (r.requestedBy) parts.push(r.requestedBy.name)
      parts.push(root.age(root.svc && root.svc.view.sort === "modified" ? r.updatedAt : r.createdAt))
      return parts.join(" · ")
    }

    Column {
      id: header
      width: parent.width
      spacing: Style.space(8)

      TopBar {
        width: parent.width
        title: "Seerr"
        icon: Glyphs.seerr
        subtitle: {
          if (!root.svc) return ""
          if (root.offline) return root.retrying ? root.t("bar.connecting") : root.t("bar.error")
          if (root.svc.connection === "connected") return root.tn("list.pendingCount", root.pending)
          if (root.svc.connection === "connecting") return root.t("bar.connecting")
          if (root.svc.connection === "unconfigured") return root.t("bar.setup")
          return root.t("bar.error")
        }
        subtitleUrgent: root.offline && !root.retrying
        // The pending count takes you to the pending requests.
        subtitleClickable: root.connected && root.pending > 0 && !!root.svc && root.svc.view.filter !== "pending"
        subtitleTooltip: root.t("filter.pending") + "  (f)"
        onSubtitleClicked: { root.cursor = 0; root.svc.setView({ filter: "pending" }) }
        showBack: false
        foreground: root.foreground; dim: root.dim; accent: root.accent; urgent: root.urgent; fontFamily: root.fontFamily
        IconButton {
          glyph: Glyphs.refresh
          tooltip: root.t("action.refresh") + "  (r)"
          spinning: !!root.svc && (root.svc.listLoading || root.svc.connection === "connecting")
          foreground: root.foreground; accent: root.accent; fontFamily: root.fontFamily
          onActivated: if (root.svc) root.svc.refresh()
        }
        IconButton {
          glyph: Glyphs.open; tooltip: root.t("action.openSeerr") + "  (o)"; enabled: !!root.svc && root.svc.baseUrl !== ""
          foreground: root.foreground; accent: root.accent; fontFamily: root.fontFamily
          onActivated: root.svc.openInBrowser(null)
        }
        IconButton {
          glyph: Glyphs.cog; tooltip: root.t("settings.title") + "  (s)"
          foreground: root.foreground; accent: root.accent; fontFamily: root.fontFamily
          onActivated: root.go("settings")
        }
      }

      // Filters: status, type, sort, direction.
      RowLayout {
        width: parent.width
        spacing: Style.space(6)
        visible: root.connected
        SyncedDropdown {
          Layout.fillWidth: true
          Layout.preferredWidth: 1
          showLabel: false
          current: root.svc ? root.svc.view.filter : "pending"
          options: Seerr.FILTERS.map(function(f) { return { value: f, label: root.t("filter." + f) } })
          foreground: root.foreground
          fontFamily: root.fontFamily
          onChanged: function(v) { root.cursor = 0; root.svc.setView({ filter: v }) }
        }
        SyncedDropdown {
          Layout.fillWidth: true
          Layout.preferredWidth: 1
          showLabel: false
          current: root.svc ? root.svc.view.mediaType : "all"
          options: Seerr.MEDIA_TYPES.map(function(f) { return { value: f, label: root.t("mediaType." + f) } })
          foreground: root.foreground
          fontFamily: root.fontFamily
          onChanged: function(v) { root.cursor = 0; root.svc.setView({ mediaType: v }) }
        }
        SyncedDropdown {
          Layout.fillWidth: true
          Layout.preferredWidth: 1
          showLabel: false
          // Sort and order in one choice, each spelled out ("Newest").
          current: root.svc ? root.svc.view.sort + ":" + root.svc.view.sortDirection : "added:desc"
          options: {
            var out = []
            for (var i = 0; i < Seerr.SORTS.length; i++)
              for (var j = 0; j < Seerr.DIRECTIONS.length; j++) {
                var k = Seerr.SORTS[i] + ":" + Seerr.DIRECTIONS[j]
                out.push({ value: k, label: root.t("sortBy." + Seerr.SORTS[i] + "." + Seerr.DIRECTIONS[j]) })
              }
            return out
          }
          foreground: root.foreground
          fontFamily: root.fontFamily
          onChanged: function(v) {
            var parts = v.split(":")
            root.cursor = 0
            root.svc.setView({ sort: parts[0], sortDirection: parts[1] })
          }
        }
      }

      TextField {
        id: search
        width: parent.width
        visible: root.connected
        placeholderText: root.t("list.search") + "  (/)"
        foreground: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        onTextChanged: if (root.svc && text !== root.svc.view.search) { root.cursor = 0; root.svc.setView({ search: text }) }
        // Enter hands the keyboard back to the list, keeping the search.
        onAccepted: if (panel.loadedContent) panel.loadedContent.forceActiveFocus()
        Connections {
          target: root.svc
          ignoreUnknownSignals: true
          function onViewChanged() { if (root.svc.view.search !== search.text) search.text = root.svc.view.search }
        }
      }

      // Seerr stopped answering: what follows is from before.
      OfflineBanner {
        width: parent.width
        visible: root.offline && root.visibleRows.length > 0
        title: root.svc && root.svc.lastOkAt > 0
          ? root.t("list.offlineSince").arg(new Date(root.svc.lastOkAt).toLocaleTimeString(Qt.locale(Commons.I18n.formatLocale), Locale.ShortFormat))
          : root.t("list.offlineTitle")
        detail: root.svc ? root.svc.lastError : ""
        retryLabel: root.t("action.retry")
        retrying: root.retrying
        foreground: root.foreground; dim: root.dim; accent: root.accent; urgent: root.urgent; fontFamily: root.fontFamily
        onRetry: root.svc.refresh()
      }
    }

    Flickable {
      id: flick
      anchors.top: header.bottom
      anchors.topMargin: Style.space(10)
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: listKeys.visible ? listKeys.top : parent.bottom
      anchors.bottomMargin: listKeys.visible ? listKeys.topMargin : 0
      contentWidth: width
      contentHeight: rowCol.implicitHeight + footer.gap + footer.implicitHeight + Style.space(4)
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
      onContentYChanged: if (root.svc && contentY + height > contentHeight - Style.space(80)) root.svc.loadMore()

      Column {
        id: rowCol
        width: flick.width
        spacing: Style.space(4)
        opacity: root.offline ? 0.45 : 1
        Behavior on opacity { NumberAnimation { duration: Style.duration(200) } }
        Repeater {
          id: rowRepeater
          model: root.visibleRows
          RequestRow {
            id: row
            required property var modelData
            required property int index
            readonly property var req: modelData
            readonly property var media: root.svc ? (root.svc.mediaRevision, root.svc.mediaFor(req)) : null
            width: rowCol.width
            title: root.svc ? root.svc.nameFor(req) : ""
            year: root.svc ? (root.svc.mediaRevision, root.svc.yearFor(req)) : ""
            is4k: !!req.is4k
            details: listRoot.rowDetails(req)
            showPoster: root.cfg.showPosters
            posterUrl: root.cfg.showPosters ? Seerr.posterUrl(media ? media.posterPath : "", "w92") : ""
            posterType: req.type
            status: Seerr.statusKey(req)
            statusLabel: root.t("statusShort." + row.status)
            statusTone: root.statusColor(row.status)
            actionable: req.status === Seerr.REQUEST_PENDING && !!root.svc && root.svc.canManage && !root.offline
            busy: !!root.svc && root.svc.isBusy(req.id)
            approveTooltip: root.t("action.approve") + "  (a)\n" + root.t("hint.shiftApprove")
            declineTooltip: root.t("action.decline") + "  (d)"
            selected: root.cursor === row.index
            keyboardActive: root.listFocused
            foreground: root.foreground; dim: root.dim; accent: root.accent; urgent: root.urgent; fontFamily: root.fontFamily
            onPointed: root.cursor = row.index
            onOpened: root.openDetail(req)
            onApproveClicked: function(mods) { root.approve(req, (mods & Qt.ShiftModifier) !== 0) }
            onDeclineClicked: root.decline(req)
          }
        }
      }

      // Below the rows, or centred in the empty list when there are none.
      Column {
        id: footer
        readonly property real gap: Style.space(6)
        y: root.visibleRows.length > 0 ? rowCol.implicitHeight + gap
                                       : Math.max(0, Math.round((flick.height - implicitHeight) / 2))
        width: flick.width
        spacing: Style.space(6)

        // Unreachable with nothing to show: say so here, with a way out.
        PlainText {
          anchors.horizontalCenter: parent.horizontalCenter
          visible: root.offline && root.visibleRows.length === 0
          text: Glyphs.warning
          color: root.retrying ? root.dim : root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.display
        }
        PlainText {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          visible: root.offline && root.visibleRows.length === 0
          text: root.t("list.offlineTitle")
          color: root.foreground
          font.family: root.fontFamily
          font.bold: true
        }
        Hint {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          visible: text !== ""
          text: {
            if (!root.svc) return ""
            if (root.offline) return root.visibleRows.length === 0 ? root.svc.lastError : ""
            if (root.svc.connection === "unconfigured") return root.t("list.setupHint")
            if (root.svc.connection !== "connected") return ""
            if (root.svc.listError) return root.svc.listError
            if (root.svc.listLoading) return root.t("list.loading")
            if (root.visibleRows.length > 0) return ""
            var v = root.svc.view
            if (v.search) return root.t("list.noMatch").arg(v.search)
            if (v.filter === "pending" && v.mediaType === "all") return root.t("list.nothingPending")
            if (v.filter === "all" && v.mediaType === "all") return root.t("list.noRequests")
            return root.t("list.emptyFilter")
          }
          color: root.svc && root.svc.listError ? root.urgent : root.dim
          font.family: root.fontFamily
        }
        Hint {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          visible: root.connected && !!root.svc && root.svc.view.search !== "" && root.visibleRows.length === 0 && !root.svc.listLoading
          text: root.t("list.clearSearch")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(6)
          visible: (root.offline && root.visibleRows.length === 0) || (!!root.svc && root.svc.connection === "unconfigured")
          ActionButton {
            visible: root.offline
            label: root.t("action.retry")
            glyph: Glyphs.retry
            primary: true
            busy: root.retrying
            foreground: root.foreground; accent: root.accent; urgent: root.urgent; fontFamily: root.fontFamily
            onActivated: root.svc.refresh()
          }
          ActionButton {
            label: root.t("settings.title")
            glyph: Glyphs.cog
            foreground: root.foreground; accent: root.accent; urgent: root.urgent; fontFamily: root.fontFamily
            onActivated: root.go("settings")
          }
        }
      }
    }

    // Pinned below the list, so it shows however long the list is.
    KeyHints {
      id: listKeys
      readonly property real topMargin: Style.space(8)
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      visible: root.connected
      text: root.t("list.keys")
      tone: root.dim
      fontFamily: root.fontFamily
    }
  }

  component DetailPage: Item {
    id: detailRoot
    readonly property var req: root.detailReq
    readonly property var media: req && root.svc ? (root.svc.mediaRevision, root.svc.mediaFor(req)) : null
    readonly property string status: Seerr.statusKey(req)
    readonly property bool busy: !!req && !!root.svc && root.svc.isBusy(req.id)
    implicitHeight: header0.implicitHeight + Style.space(10) + detailColumn.implicitHeight
                    + (detailKeys.visible ? detailKeys.topMargin + detailKeys.implicitHeight : 0)

    TopBar {
      id: header0
      width: parent.width
      title: detailRoot.req ? root.t("detail.title") : root.t("list.loading")
      showBack: true
      backTooltip: root.t("action.back") + "  (Esc)"
      foreground: root.foreground; dim: root.dim; accent: root.accent; urgent: root.urgent; fontFamily: root.fontFamily
      onBack: root.back()
      IconButton {
        glyph: Glyphs.open; tooltip: root.t("action.openSeerr") + "  (o)"; enabled: !!detailRoot.req
        foreground: root.foreground; accent: root.accent; fontFamily: root.fontFamily
        onActivated: root.svc.openInBrowser(detailRoot.req)
      }
    }

    Flickable {
      anchors.top: header0.bottom
      anchors.topMargin: Style.space(10)
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: detailKeys.visible ? detailKeys.top : parent.bottom
      anchors.bottomMargin: detailKeys.visible ? detailKeys.topMargin : 0
      contentWidth: width
      contentHeight: detailColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: detailColumn
        width: parent.width
        spacing: Style.space(12)
        visible: !!detailRoot.req

        Row {
          width: parent.width
          spacing: Style.space(12)
          Poster {
            visible: root.cfg.showPosters
            width: Style.space(92)
            height: Style.space(138)
            url: root.cfg.showPosters ? Seerr.posterUrl(detailRoot.media ? detailRoot.media.posterPath : "", "w185") : ""
            type: detailRoot.req ? detailRoot.req.type : "movie"
            foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily
          }
          Column {
            width: parent.width - (root.cfg.showPosters ? Style.space(104) : 0)
            spacing: Style.space(5)
            PlainText {
              width: parent.width
              text: detailRoot.media ? detailRoot.media.title : ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              wrapMode: Text.WordWrap
              maximumLineCount: 3
              elide: Text.ElideRight
            }
            PlainText {
              width: parent.width
              color: root.dim
              font.family: root.fontFamily
              text: {
                var r = detailRoot.req, m = detailRoot.media
                if (!r) return ""
                var parts = []
                if (m && m.year) parts.push(m.year)
                parts.push(r.type === "tv" ? root.t("type.tv") : root.t("type.movie"))
                if (r.is4k) parts.push("4K")
                if (m && m.runtime) parts.push(root.t("detail.runtime").arg(m.runtime))
                if (m && m.seasonCount) parts.push(root.tn("detail.seasonCount", m.seasonCount))
                if (m && m.vote) parts.push("★ " + Commons.I18n.formatNumber(m.vote, 1))
                return parts.join(" · ")
              }
            }
            PlainText {
              width: parent.width
              visible: text !== ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              text: detailRoot.media ? detailRoot.media.genres.join(", ") : ""
              elide: Text.ElideRight
            }
            StatusBadge {
              status: detailRoot.status
              label: root.t("status." + detailRoot.status)
              tone: root.statusColor(detailRoot.status)
              fontFamily: root.fontFamily
            }
          }
        }

        Column {
          width: parent.width
          spacing: Style.spacing.labelGap
          InfoPair {
            label: root.t("detail.requestedBy"); value: detailRoot.req && detailRoot.req.requestedBy ? detailRoot.req.requestedBy.name : ""
            foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily
          }
          InfoPair {
            label: root.t("detail.requested"); value: detailRoot.req ? root.longDate(detailRoot.req.createdAt) : ""
            foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily
          }
          InfoPair {
            visible: !!detailRoot.req && !!detailRoot.req.modifiedBy
            label: detailRoot.status === "declined" ? root.t("detail.declinedBy") : root.t("detail.modifiedBy")
            value: detailRoot.req && detailRoot.req.modifiedBy ? detailRoot.req.modifiedBy.name : ""
            foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily
          }
          InfoPair {
            visible: !!detailRoot.req && detailRoot.req.updatedAt > detailRoot.req.createdAt + 1000
            label: root.t("detail.updated")
            value: detailRoot.req ? root.longDate(detailRoot.req.updatedAt) : ""
            foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily
          }
          InfoPair {
            visible: !!detailRoot.req && detailRoot.req.type === "tv"
            label: root.t("detail.seasons")
            value: detailRoot.req ? Seerr.seasonsLabel(detailRoot.req.seasons) : ""
            foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily
          }
          InfoPair {
            visible: !!detailRoot.req && detailRoot.req.rootFolder !== ""
            label: root.t("detail.rootFolder")
            value: detailRoot.req ? detailRoot.req.rootFolder : ""
            foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily
          }
        }

        PanelSeparator { foreground: root.foreground; visible: overview.text !== "" }

        PlainText {
          id: overview
          width: parent.width
          visible: text !== ""
          text: detailRoot.media ? detailRoot.media.overview : ""
          color: root.foreground
          font.family: root.fontFamily
          wrapMode: Text.WordWrap
          font.pixelSize: Style.font.bodySmall
          lineHeight: 1.15
        }

        Flow {
          width: parent.width
          spacing: Style.space(6)
          visible: !!detailRoot.req
          ActionButton {
            visible: !!detailRoot.req && detailRoot.req.status === Seerr.REQUEST_PENDING && !!root.svc && root.svc.canManage
            label: root.t("action.approve")
            glyph: Glyphs.check
            primary: true
            busy: detailRoot.busy
            tooltip: root.t("hint.shiftApprove")
            foreground: root.foreground; accent: root.accent; urgent: root.urgent; fontFamily: root.fontFamily
            onActivated: function(mods) { root.approve(detailRoot.req, (mods & Qt.ShiftModifier) !== 0) }
          }
          ActionButton {
            visible: !!detailRoot.req && detailRoot.req.status === Seerr.REQUEST_PENDING && !!root.svc && root.svc.canManage
            label: root.t("action.decline")
            glyph: Glyphs.close
            busy: detailRoot.busy
            foreground: root.foreground; accent: root.accent; urgent: root.urgent; fontFamily: root.fontFamily
            onActivated: root.decline(detailRoot.req)
          }
          ActionButton {
            visible: !!detailRoot.req && detailRoot.req.status === Seerr.REQUEST_FAILED && !!root.svc && root.svc.canManage
            label: root.t("action.retry")
            glyph: Glyphs.retry
            busy: detailRoot.busy
            foreground: root.foreground; accent: root.accent; urgent: root.urgent; fontFamily: root.fontFamily
            onActivated: root.svc.retry(detailRoot.req.id)
          }
          ActionButton {
            label: root.t("action.delete")
            glyph: Glyphs.trash
            danger: true
            busy: detailRoot.busy
            foreground: root.foreground; accent: root.accent; urgent: root.urgent; fontFamily: root.fontFamily
            onActivated: root.remove(detailRoot.req)
          }
        }
      }
    }

    // Pinned below the details, so it shows even when they scroll.
    KeyHints {
      id: detailKeys
      readonly property real topMargin: Style.space(10)
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      visible: !!detailRoot.req
      text: {
        var r = detailRoot.req
        if (r && r.status === Seerr.REQUEST_PENDING) return root.t("detail.keys")
        if (r && r.status === Seerr.REQUEST_FAILED) return root.t("detail.keysFailed")
        return root.t("detail.keysDone")
      }
      tone: root.dim
      fontFamily: root.fontFamily
    }
  }

  component ApprovePage: Item {
    id: approveRoot
    readonly property var req: root.formReq
    readonly property bool busy: !!req && !!root.svc && root.svc.isBusy(req.id)
    implicitHeight: header0.implicitHeight + Style.space(10) + formColumn.implicitHeight
                    + approveKeys.topMargin + approveKeys.implicitHeight

    TopBar {
      id: header0
      width: parent.width
      title: root.t("approve.title")
      showBack: true
      backTooltip: root.t("action.back") + "  (Esc)"
      foreground: root.foreground; dim: root.dim; accent: root.accent; urgent: root.urgent; fontFamily: root.fontFamily
      onBack: root.back()
    }

    Flickable {
      anchors.top: header0.bottom
      anchors.topMargin: Style.space(10)
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: approveKeys.top
      anchors.bottomMargin: approveKeys.topMargin
      contentWidth: width
      contentHeight: formColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: formColumn
        width: parent.width
        spacing: Style.space(10)

        // What is being approved.
        RowLayout {
          width: parent.width
          spacing: Style.space(10)
          visible: !!approveRoot.req
          Poster {
            visible: root.cfg.showPosters
            Layout.preferredWidth: Style.space(36)
            Layout.preferredHeight: Style.space(54)
            url: root.cfg.showPosters ? Seerr.posterUrl(root.formMedia ? root.formMedia.posterPath : "", "w92") : ""
            type: approveRoot.req ? approveRoot.req.type : "movie"
            foreground: root.foreground; dim: root.dim; fontFamily: root.fontFamily
          }
          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(3)
            PlainText {
              Layout.fillWidth: true
              text: approveRoot.req && root.svc ? root.svc.titleFor(approveRoot.req) : ""
              color: root.foreground
              font.family: root.fontFamily
              font.bold: true
              elide: Text.ElideRight
            }
            PlainText {
              Layout.fillWidth: true
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              text: {
                var r = approveRoot.req
                if (!r) return ""
                var parts = [r.type === "tv" ? root.t("type.tv") : root.t("type.movie")]
                if (r.is4k) parts.push("4K")
                if (r.requestedBy) parts.push(root.t("notify.by").arg(r.requestedBy.name))
                return parts.join(" · ")
              }
            }
          }
        }

        Hint {
          width: parent.width
          visible: root.formLoading
          text: root.t("approve.loading")
          color: root.dim
          font.family: root.fontFamily
        }
        Hint {
          width: parent.width
          visible: root.formError !== ""
          text: root.formError
          color: root.urgent
          font.family: root.fontFamily
        }

        SyncedDropdown {
          width: parent.width
          visible: root.formServers.length > 0 && !!root.form
          label: approveRoot.req && approveRoot.req.type === "tv" ? root.t("approve.sonarr") : root.t("approve.radarr")
          current: root.form ? String(root.form.serverId) : ""
          options: root.formServers.map(function(s) { return { value: String(s.id), label: s.isDefault ? root.t("approve.defaultServer").arg(s.name) : s.name } })
          foreground: root.foreground
          fontFamily: root.fontFamily
          onChanged: function(v) { root.selectServer(parseInt(v, 10)) }
        }
        SyncedDropdown {
          width: parent.width
          visible: !!root.form && !!root.formDetails
          label: root.t("approve.profile")
          current: root.form ? String(root.form.profileId) : ""
          options: root.formDetails ? root.formDetails.profiles.map(function(p) { return { value: String(p.id), label: p.name } }) : []
          foreground: root.foreground
          fontFamily: root.fontFamily
          onChanged: function(v) { root.setForm({ profileId: parseInt(v, 10) }) }
        }
        SyncedDropdown {
          width: parent.width
          visible: !!root.form && !!root.formDetails
          label: root.t("approve.rootFolder")
          current: root.form ? root.form.rootFolder : ""
          options: root.formDetails ? root.formDetails.rootFolders.map(function(f) {
            var free = f.freeSpace >= 0 ? "  (" + root.t("approve.free").arg(Seerr.formatBytes(f.freeSpace, Commons.I18n.formatNumber)) + ")" : ""
            return { value: f.path, label: f.path + free }
          }) : []
          foreground: root.foreground
          fontFamily: root.fontFamily
          onChanged: function(v) { root.setForm({ rootFolder: v }) }
        }
        SyncedDropdown {
          width: parent.width
          visible: !!root.form && !!root.formDetails && !!root.formDetails.languageProfiles && root.formDetails.languageProfiles.length > 0
          label: root.t("approve.languageProfile")
          current: root.form ? String(root.form.languageProfileId) : ""
          options: root.formDetails && root.formDetails.languageProfiles ? root.formDetails.languageProfiles.map(function(p) { return { value: String(p.id), label: p.name } }) : []
          foreground: root.foreground
          fontFamily: root.fontFamily
          onChanged: function(v) { root.setForm({ languageProfileId: parseInt(v, 10) }) }
        }

        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: !!root.form && !!root.formDetails && root.formDetails.tags.length > 0
          FieldLabel { text: root.t("approve.tags"); color: root.dim; font.family: root.fontFamily }
          Flow {
            width: parent.width
            spacing: Style.space(5)
            Repeater {
              model: root.formDetails ? root.formDetails.tags : []
              Chip {
                required property var modelData
                label: modelData.name
                selected: !!root.form && root.form.tags.indexOf(modelData.id) !== -1
                foreground: root.foreground; accent: root.accent; fontFamily: root.fontFamily
                onActivated: root.setForm({ tags: Seerr.toggleInList(root.form.tags, modelData.id) })
              }
            }
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: !!root.form && !!approveRoot.req && approveRoot.req.type === "tv"
          FieldLabel { text: root.t("approve.seasons"); color: root.dim; font.family: root.fontFamily }
          Flow {
            width: parent.width
            spacing: Style.space(5)
            Repeater {
              model: {
                var m = root.formMedia
                var list = m && m.seasons.length ? m.seasons.filter(function(s) { return s.seasonNumber > 0 }) : []
                if (list.length === 0 && approveRoot.req) list = approveRoot.req.seasons.map(function(n) { return { seasonNumber: n, episodeCount: 0 } })
                return list
              }
              Chip {
                required property var modelData
                label: root.t("approve.season").arg(modelData.seasonNumber)
                tooltip: modelData.episodeCount ? root.tn("approve.episodes", modelData.episodeCount) : ""
                selected: !!root.form && root.form.seasons.indexOf(modelData.seasonNumber) !== -1
                foreground: root.foreground; accent: root.accent; fontFamily: root.fontFamily
                onActivated: root.setForm({ seasons: Seerr.toggleInList(root.form.seasons, modelData.seasonNumber) })
              }
            }
          }
        }

        Flow {
          width: parent.width
          spacing: Style.space(6)
          ActionButton {
            label: root.t("action.approve")
            glyph: Glyphs.check
            primary: true
            busy: approveRoot.busy
            enabled: !!root.form && !root.formLoading && Seerr.formProblem(approveRoot.req, root.form) === ""
            tooltip: root.t("hint.shiftApprove")
            foreground: root.foreground; accent: root.accent; urgent: root.urgent; fontFamily: root.fontFamily
            onActivated: function(mods) { root.submitForm((mods & Qt.ShiftModifier) !== 0) }
          }
          ActionButton {
            label: root.t("approve.quick")
            glyph: Glyphs.bolt
            busy: approveRoot.busy
            visible: root.formError !== "" || !root.form
            foreground: root.foreground; accent: root.accent; urgent: root.urgent; fontFamily: root.fontFamily
            onActivated: root.submitForm(true)
          }
          ActionButton {
            label: root.t("action.cancel")
            foreground: root.foreground; accent: root.accent; urgent: root.urgent; fontFamily: root.fontFamily
            onActivated: root.back()
          }
        }
      }
    }

    // Pinned below the form.
    KeyHints {
      id: approveKeys
      readonly property real topMargin: Style.space(10)
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      text: root.t("approve.keys")
      tone: root.dim
      fontFamily: root.fontFamily
    }
  }

  component SettingsPage: Item {
    id: settingsRoot
    implicitHeight: header0.implicitHeight + Style.space(10) + settingsColumn.implicitHeight
                    + settingsKeys.topMargin + settingsKeys.implicitHeight


    function intervalLabel(sec) {
      return sec < 60 ? root.tn("settings.seconds", sec) : root.tn("settings.minutes", Math.round(sec / 60))
    }

    TopBar {
      id: header0
      width: parent.width
      title: root.t("settings.title")
      showBack: true
      backTooltip: root.t("action.back") + "  (Esc)"
      foreground: root.foreground; dim: root.dim; accent: root.accent; urgent: root.urgent; fontFamily: root.fontFamily
      onBack: root.back()
    }

    Flickable {
      anchors.top: header0.bottom
      anchors.topMargin: Style.space(10)
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: settingsKeys.top
      anchors.bottomMargin: settingsKeys.topMargin
      contentWidth: width
      contentHeight: settingsColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: settingsColumn
        width: parent.width
        spacing: Style.space(10)

        // -------- connection
        PanelSectionHeader { text: root.t("settings.connection"); foreground: root.foreground; fontFamily: root.fontFamily }

        FieldLabel { text: root.t("settings.url"); color: root.dim; font.family: root.fontFamily }
        RowLayout {
          width: parent.width
          spacing: Style.space(6)
          TextField {
            id: urlField
            Layout.fillWidth: true
            text: root.cfg.url
            placeholderText: "https://seerr.example.com"
            foreground: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
            onAccepted: saveUrl.activated(0)
          }
          ActionButton {
            id: saveUrl
            label: root.t("action.save")
            enabled: urlField.text.trim() !== root.cfg.url
            foreground: root.foreground; accent: root.accent; urgent: root.urgent; fontFamily: root.fontFamily
            onActivated: {
              var n = Seerr.normalizeBaseUrl(urlField.text)
              if (urlField.text.trim() === "") { root.saveSetting({ url: "" }); return }
              if (!n.ok) { root.flash(root.t("settings.urlInvalid"), true); return }
              urlField.text = n.url
              root.saveSetting({ url: n.url })
            }
          }
        }
        Hint {
          width: parent.width
          visible: !!root.svc && root.svc.exposed
          text: root.t("settings.httpWarning")
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        FieldLabel { text: root.t("settings.apiKey"); color: root.dim; font.family: root.fontFamily }
        RowLayout {
          width: parent.width
          spacing: Style.space(6)
          TextField {
            id: keyField
            Layout.fillWidth: true
            password: true
            placeholderText: root.svc && root.svc.keyState === "ok" ? root.t("settings.keyStored") : root.t("settings.keyPlaceholder")
            foreground: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
            onAccepted: saveKey.activated(0)
          }
          ActionButton {
            id: saveKey
            label: root.t("action.save")
            glyph: Glyphs.lock
            enabled: keyField.text.trim() !== ""
            foreground: root.foreground; accent: root.accent; urgent: root.urgent; fontFamily: root.fontFamily
            onActivated: {
              if (root.svc && root.svc.storeKey(keyField.text)) keyField.text = ""
              else root.flash(root.svc ? root.svc.keyMessage : "", true)
            }
          }
          // Rarely used: kept plain rather than alarming red.
          ActionButton {
            label: root.t("action.remove")
            visible: !!root.svc && root.svc.keyState === "ok"
            foreground: root.foreground; accent: root.accent; urgent: root.urgent; fontFamily: root.fontFamily
            onActivated: root.svc.clearKey()
          }
        }
        Hint {
          width: parent.width
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          text: root.t("settings.keyHelp")
        }
        Hint {
          width: parent.width
          text: {
            if (!root.svc) return ""
            if (root.svc.keyMessage) return root.svc.keyMessage
            if (root.svc.connection === "connected")
              return root.t("settings.connectedAs").arg(root.svc.me ? root.svc.me.name : "?")
                + (root.svc.canManage ? "" : "  —  " + root.t("settings.noManage"))
            if (root.svc.connection === "connecting") return root.t("bar.connecting")
            if (root.svc.connection === "error") return root.svc.lastError
            if (!root.svc.baseUrl) return root.t("settings.noUrl")
            if (root.svc.keyState === "missing") return root.t("settings.noKey")
            return ""
          }
          color: !!root.svc && (root.svc.connection === "error" || root.svc.keyMessage !== "" || (root.svc.connection === "connected" && !root.svc.canManage)) ? root.urgent : root.dim
          font.family: root.fontFamily
        }

        BoundChoice {
          key: "refreshIntervalSec"
          numeric: true
          label: root.t("settings.refreshInterval")
          options: [15, 30, 60, 120, 300, 600, 1800, 3600].map(function(v) { return { value: String(v), label: settingsRoot.intervalLabel(v) } })
        }

        // -------- notifications
        PanelSeparator { foreground: root.foreground }
        PanelSectionHeader { text: root.t("settings.notifications"); foreground: root.foreground; fontFamily: root.fontFamily }
        BoundToggle { key: "notifyNewRequests"; label: root.t("settings.notifyNewRequests"); description: root.t("settings.notifyNewRequestsHelp") }
        BoundToggle { key: "notifyStatusChanges"; label: root.t("settings.notifyStatusChanges"); description: root.t("settings.notifyStatusChangesHelp") }
        BoundToggle { key: "notifyPoster"; label: root.t("settings.notifyPoster"); description: root.t("settings.notifyPosterHelp") }
        BoundChoice {
          key: "notifyUrgency"
          label: root.t("settings.notifyUrgency")
          options: ["low", "normal", "critical"].map(function(v) { return { value: v, label: root.t("urgency." + v) } })
        }
        BoundChoice {
          key: "notifyGroupThreshold"
          numeric: true
          label: root.t("settings.notifyGroupThreshold")
          options: [1, 2, 3, 4, 5, 10, 20].map(function(v) { return { value: String(v), label: v === 1 ? root.t("settings.groupAlways") : root.tn("settings.groupFrom", v) } })
        }

        // -------- defaults
        PanelSeparator { foreground: root.foreground }
        PanelSectionHeader { text: root.t("settings.defaults"); foreground: root.foreground; fontFamily: root.fontFamily }
        BoundChoice {
          key: "defaultFilter"
          label: root.t("settings.defaultFilter")
          options: Seerr.FILTERS.map(function(f) { return { value: f, label: root.t("filter." + f) } })
        }
        BoundChoice {
          key: "defaultMediaType"
          label: root.t("settings.defaultMediaType")
          options: Seerr.MEDIA_TYPES.map(function(f) { return { value: f, label: root.t("mediaType." + f) } })
        }
        BoundChoice {
          key: "defaultSort"
          label: root.t("settings.defaultSort")
          options: Seerr.SORTS.map(function(f) { return { value: f, label: root.t("sort." + f) } })
        }
        BoundChoice {
          key: "defaultSortDirection"
          label: root.t("settings.defaultSortDirection")
          options: Seerr.DIRECTIONS.map(function(f) { return { value: f, label: root.t("sort." + f) } })
        }
        BoundChoice {
          key: "pageSize"
          numeric: true
          label: root.t("settings.pageSize")
          options: [10, 20, 30, 50, 100].map(function(v) { return { value: String(v), label: String(v) } })
        }

        // -------- display
        PanelSeparator { foreground: root.foreground }
        PanelSectionHeader { text: root.t("settings.display"); foreground: root.foreground; fontFamily: root.fontFamily }
        BoundToggle { key: "showPosters"; label: root.t("settings.showPosters"); description: root.t("settings.showPostersHelp") }
        BoundToggle { key: "confirmDecline"; label: root.t("settings.confirmDecline") }
      }
    }

    // Pinned below the settings.
    KeyHints {
      id: settingsKeys
      readonly property real topMargin: Style.space(10)
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      text: root.t("settings.keys")
      tone: root.dim
      fontFamily: root.fontFamily
    }
  }

  // The settings page's controls, bound to the panel's settings and theme.
  component BoundToggle: SettingToggle {
    values: root.cfg
    foreground: root.foreground
    fontFamily: root.fontFamily
    onSave: function(patch) { root.saveSetting(patch) }
  }

  component BoundChoice: SettingChoice {
    values: root.cfg
    foreground: root.foreground
    fontFamily: root.fontFamily
    onSave: function(patch) { root.saveSetting(patch) }
  }

  // ================================================================ parts

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
