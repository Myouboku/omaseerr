import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "model/Seerr.js" as Seerr

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
  readonly property bool problem: !svc || svc.connection === "error" || svc.connection === "unconfigured"

  // ---------------------------------------------------------------- glyphs

  readonly property string gSeerr: "\u{f0fce}"
  readonly property string gMovie: "\u{f0381}"
  readonly property string gTv: "\u{f0502}"
  readonly property string gCheck: "\u{f012c}"
  readonly property string gClose: "\u{f0156}"
  readonly property string gRefresh: "\u{f0450}"
  readonly property string gCog: "\u{f0493}"
  readonly property string gDelete: "\u{f01b4}"
  readonly property string gOpen: "\u{f03cc}"
  readonly property string gBack: "\u{f004d}"
  readonly property string gAlert: "\u{f0028}"
  readonly property string gKey: "\u{f0306}"
  readonly property string gBolt: "\u{f140b}"
  readonly property string gSearch: "\u{f0349}"
  readonly property string gSortDesc: "\u{f04bd}"
  readonly property string gSortAsc: "\u{f04bc}"
  readonly property string gRetry: "\u{f0450}"
  readonly property string gLock: "\u{f033e}"

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

  function moveCursor(dy) {
    if (page !== "list" || visibleRows.length === 0) return
    cursor = Math.max(0, Math.min(visibleRows.length - 1, cursor + dy))
    scrollCursorIntoView()
    if (dy > 0 && cursor >= visibleRows.length - 3 && svc) svc.loadMore()
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
      if (!ok) root.flash(message, true)
      else if (action === "approve" && root.page === "approve" && root.detailId === requestId) root.go("detail")
    }
  }

  // A short line under the header for results and errors.
  property string flashText: ""
  property bool flashError: false
  function flash(text, error) {
    flashText = String(text || "")
    flashError = !!error
    flashTimer.restart()
  }
  Timer {
    id: flashTimer
    interval: 4000
    onTriggered: root.flashText = ""
  }

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
        root.formServers = servers.filter(function(s) { return s.is4k === req.is4k })
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
    if (!server) return
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
      if (page === "list" && content && content.searchField && content.searchField.activeFocus) {
        if (svc && svc.view.search) svc.setView({ search: "" })
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
      if (!root.svc) return "Seerr"
      if (root.svc.connection === "connected") return root.tn("bar.pending", root.pending)
      if (root.svc.connection === "unconfigured") return root.t("bar.setup")
      if (root.svc.connection === "connecting") return root.t("bar.connecting")
      return root.svc.lastError || root.t("bar.error")
    }
    iconComponent: Component {
      Item {
        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: root.gSeerr
          color: root.problem ? Qt.darker(root.barForeground, 1.55) : root.barForeground
          font.family: root.fontFamily
          font.pixelSize: button.iconSize
        }
        Rectangle {
          readonly property bool shown: !!root.svc && root.cfg.showBadge
            && ((root.connected && (root.pending > 0 || root.cfg.badgeWhenEmpty)) || (root.svc.connection === "error"))
          visible: shown
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.rightMargin: -Math.round(width * 0.45)
          anchors.topMargin: -Math.round(height * 0.3)
          height: Math.max(Style.space(11), Math.round(button.iconSize * 0.8))
          width: Math.max(height, badgeText.implicitWidth + Style.space(5))
          radius: height / 2
          color: root.svc && root.svc.connection === "error" ? root.urgent : root.accent
          Text {
            id: badgeText
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: root.svc && root.svc.connection === "error" ? "!" : (root.pending > 99 ? "99+" : String(root.pending))
            color: Commons.Color.background
            font.family: root.fontFamily
            font.pixelSize: Math.round(parent.height * 0.78)
            font.bold: true
          }
        }
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
      Keys.onPressed: function(event) { root.handleKey(event) }

      ListPage { id: listPage; anchors.fill: parent; visible: root.page === "list" }
      DetailPage { id: detailPage; anchors.fill: parent; visible: root.page === "detail" }
      ApprovePage { id: approvePage; anchors.fill: parent; visible: root.page === "approve" }
      SettingsPage { id: settingsPage; anchors.fill: parent; visible: root.page === "settings" }

      ConfirmDialog {
        id: confirmDialog
        anchors.fill: parent
        z: 10
        opened: root.confirmOpen
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

    Column {
      id: header
      width: parent.width
      spacing: Style.space(8)

      TopBar {
        width: parent.width
        title: "Seerr"
        subtitle: {
          if (!root.svc) return ""
          if (root.svc.connection === "connected") return root.tn("list.pendingCount", root.pending)
          if (root.svc.connection === "connecting") return root.t("bar.connecting")
          if (root.svc.connection === "unconfigured") return root.t("bar.setup")
          return root.svc.lastError
        }
        subtitleUrgent: !!root.svc && root.svc.connection === "error"
        showBack: false
        IconButton { glyph: root.gRefresh; tooltip: root.t("action.refresh") + "  (r)"; onActivated: if (root.svc) root.svc.refresh() }
        IconButton { glyph: root.gOpen; tooltip: root.t("action.openSeerr") + "  (o)"; enabled: !!root.svc && root.svc.baseUrl !== ""; onActivated: root.svc.openInBrowser(null) }
        IconButton { glyph: root.gCog; tooltip: root.t("settings.title") + "  (s)"; onActivated: root.go("settings") }
      }

      // Filters: status, type, sort, direction.
      RowLayout {
        width: parent.width
        spacing: Style.space(6)
        visible: root.connected
        Dropdown {
          Layout.fillWidth: true
          Layout.preferredWidth: 1
          showLabel: false
          value: root.svc ? root.svc.view.filter : "pending"
          options: Seerr.FILTERS.map(function(f) { return { value: f, label: root.t("filter." + f) } })
          foreground: root.foreground
          fontFamily: root.fontFamily
          onChanged: function(v) { root.cursor = 0; root.svc.setView({ filter: v }) }
        }
        Dropdown {
          Layout.fillWidth: true
          Layout.preferredWidth: 1
          showLabel: false
          value: root.svc ? root.svc.view.mediaType : "all"
          options: Seerr.MEDIA_TYPES.map(function(f) { return { value: f, label: root.t("mediaType." + f) } })
          foreground: root.foreground
          fontFamily: root.fontFamily
          onChanged: function(v) { root.cursor = 0; root.svc.setView({ mediaType: v }) }
        }
        Dropdown {
          Layout.fillWidth: true
          Layout.preferredWidth: 1
          showLabel: false
          value: root.svc ? root.svc.view.sort : "added"
          options: Seerr.SORTS.map(function(f) { return { value: f, label: root.t("sort." + f) } })
          foreground: root.foreground
          fontFamily: root.fontFamily
          onChanged: function(v) { root.cursor = 0; root.svc.setView({ sort: v }) }
        }
        IconButton {
          glyph: root.svc && root.svc.view.sortDirection === "asc" ? root.gSortAsc : root.gSortDesc
          tooltip: (root.svc && root.svc.view.sortDirection === "asc" ? root.t("sort.asc") : root.t("sort.desc")) + "  (i)"
          onActivated: { root.cursor = 0; root.svc.setView({ sortDirection: root.svc.view.sortDirection === "asc" ? "desc" : "asc" }) }
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

      FlashLine { width: parent.width }
    }

    Flickable {
      id: flick
      anchors.top: header.bottom
      anchors.topMargin: Style.space(10)
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      contentWidth: width
      contentHeight: rowCol.implicitHeight + footer.anchors.topMargin + footer.implicitHeight + Style.space(4)
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
      onContentYChanged: if (root.svc && contentY + height > contentHeight - Style.space(80)) root.svc.loadMore()

      Column {
        id: rowCol
        width: flick.width
        spacing: Style.space(4)
        Repeater {
          id: rowRepeater
          model: root.visibleRows
          RequestRow {
            required property var modelData
            required property int index
            width: rowCol.width
            req: modelData
            rowIndex: index
          }
        }
      }

      Column {
        id: footer
        anchors.top: rowCol.bottom
        anchors.topMargin: Style.space(6)
        width: flick.width
        spacing: Style.space(6)

        Hint {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          visible: text !== ""
          text: {
            if (!root.svc) return ""
            if (root.svc.connection === "unconfigured") return root.t("list.setupHint")
            if (root.svc.connection !== "connected") return ""
            if (root.svc.listError) return root.svc.listError
            if (root.svc.listLoading) return root.t("list.loading")
            if (root.visibleRows.length === 0) return root.t("list.empty")
            return ""
          }
          color: root.svc && root.svc.listError ? root.urgent : root.dim
        }
        ActionButton {
          anchors.horizontalCenter: parent.horizontalCenter
          visible: !!root.svc && root.svc.connection === "unconfigured"
          label: root.t("settings.title")
          glyph: root.gCog
          onActivated: root.go("settings")
        }
        Hint {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          visible: root.connected && root.visibleRows.length > 0
          text: root.t("list.keys")
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  component DetailPage: Item {
    id: detailRoot
    readonly property var req: root.detailReq
    readonly property var media: req && root.svc ? (root.svc.mediaRevision, root.svc.mediaFor(req)) : null
    readonly property string status: Seerr.statusKey(req)
    readonly property bool busy: !!req && !!root.svc && root.svc.isBusy(req.id)
    implicitHeight: header0.implicitHeight + Style.space(10) + detailColumn.implicitHeight

    TopBar {
      id: header0
      width: parent.width
      title: detailRoot.req ? root.t("detail.title").arg(detailRoot.req.id) : root.t("list.loading")
      showBack: true
      IconButton { glyph: root.gOpen; tooltip: root.t("action.openSeerr") + "  (o)"; enabled: !!detailRoot.req; onActivated: root.svc.openInBrowser(detailRoot.req) }
    }

    Flickable {
      anchors.top: header0.bottom
      anchors.topMargin: Style.space(10)
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
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
            path: detailRoot.media ? detailRoot.media.posterPath : ""
            size: "w185"
            type: detailRoot.req ? detailRoot.req.type : "movie"
          }
          Column {
            width: parent.width - (root.cfg.showPosters ? Style.space(104) : 0)
            spacing: Style.space(5)
            PlainText {
              width: parent.width
              text: detailRoot.media ? detailRoot.media.title : ""
              font.pixelSize: Style.font.heading
              wrapMode: Text.WordWrap
              maximumLineCount: 3
              elide: Text.ElideRight
            }
            PlainText {
              width: parent.width
              color: root.dim
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
              font.pixelSize: Style.font.bodySmall
              text: detailRoot.media ? detailRoot.media.genres.join(", ") : ""
              elide: Text.ElideRight
            }
            StatusBadge { status: detailRoot.status }
          }
        }

        Column {
          width: parent.width
          spacing: Style.spacing.labelGap
          InfoPair { label: root.t("detail.requestedBy"); value: detailRoot.req && detailRoot.req.requestedBy ? detailRoot.req.requestedBy.name : "" }
          InfoPair { label: root.t("detail.requested"); value: detailRoot.req ? root.longDate(detailRoot.req.createdAt) : "" }
          InfoPair {
            visible: !!detailRoot.req && !!detailRoot.req.modifiedBy
            label: detailRoot.status === "declined" ? root.t("detail.declinedBy") : root.t("detail.modifiedBy")
            value: detailRoot.req && detailRoot.req.modifiedBy ? detailRoot.req.modifiedBy.name : ""
          }
          InfoPair {
            visible: !!detailRoot.req && detailRoot.req.updatedAt > detailRoot.req.createdAt + 1000
            label: root.t("detail.updated")
            value: detailRoot.req ? root.longDate(detailRoot.req.updatedAt) : ""
          }
          InfoPair {
            visible: !!detailRoot.req && detailRoot.req.type === "tv"
            label: root.t("detail.seasons")
            value: detailRoot.req ? Seerr.seasonsLabel(detailRoot.req.seasons) : ""
          }
          InfoPair {
            visible: !!detailRoot.req && detailRoot.req.rootFolder !== ""
            label: root.t("detail.rootFolder")
            value: detailRoot.req ? detailRoot.req.rootFolder : ""
          }
        }

        PanelSeparator { foreground: root.foreground; visible: overview.text !== "" }

        PlainText {
          id: overview
          width: parent.width
          visible: text !== ""
          text: detailRoot.media ? detailRoot.media.overview : ""
          wrapMode: Text.WordWrap
          font.pixelSize: Style.font.bodySmall
          lineHeight: 1.15
        }

        FlashLine { width: parent.width }

        Flow {
          width: parent.width
          spacing: Style.space(6)
          visible: !!detailRoot.req
          ActionButton {
            visible: !!detailRoot.req && detailRoot.req.status === Seerr.REQUEST_PENDING && !!root.svc && root.svc.canManage
            label: root.t("action.approve")
            glyph: root.gCheck
            primary: true
            busy: detailRoot.busy
            tooltip: root.t("hint.shiftApprove")
            onActivated: function(mods) { root.approve(detailRoot.req, (mods & Qt.ShiftModifier) !== 0) }
          }
          ActionButton {
            visible: !!detailRoot.req && detailRoot.req.status === Seerr.REQUEST_PENDING && !!root.svc && root.svc.canManage
            label: root.t("action.decline")
            glyph: root.gClose
            busy: detailRoot.busy
            onActivated: root.decline(detailRoot.req)
          }
          ActionButton {
            visible: !!detailRoot.req && detailRoot.req.status === Seerr.REQUEST_FAILED && !!root.svc && root.svc.canManage
            label: root.t("action.retry")
            glyph: root.gRetry
            busy: detailRoot.busy
            onActivated: root.svc.retry(detailRoot.req.id)
          }
          ActionButton {
            label: root.t("action.delete")
            glyph: root.gDelete
            danger: true
            busy: detailRoot.busy
            onActivated: root.remove(detailRoot.req)
          }
        }
        Hint {
          width: parent.width
          text: detailRoot.req && detailRoot.req.status === Seerr.REQUEST_PENDING ? root.t("detail.keys") : root.t("detail.keysDone")
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  component ApprovePage: Item {
    id: approveRoot
    readonly property var req: root.formReq
    readonly property bool busy: !!req && !!root.svc && root.svc.isBusy(req.id)
    implicitHeight: header0.implicitHeight + Style.space(10) + formColumn.implicitHeight

    TopBar {
      id: header0
      width: parent.width
      title: root.t("approve.title")
      subtitle: approveRoot.req && root.svc ? root.svc.titleFor(approveRoot.req) + (approveRoot.req.is4k ? " · 4K" : "") : ""
      showBack: true
    }

    Flickable {
      anchors.top: header0.bottom
      anchors.topMargin: Style.space(10)
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
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

        Hint {
          width: parent.width
          visible: root.formLoading
          text: root.t("approve.loading")
        }
        Hint {
          width: parent.width
          visible: root.formError !== ""
          text: root.formError
          color: root.urgent
        }

        Dropdown {
          width: parent.width
          visible: root.formServers.length > 0 && !!root.form
          label: approveRoot.req && approveRoot.req.type === "tv" ? root.t("approve.sonarr") : root.t("approve.radarr")
          value: root.form ? String(root.form.serverId) : ""
          options: root.formServers.map(function(s) { return { value: String(s.id), label: s.name + (s.isDefault ? " ★" : "") } })
          foreground: root.foreground
          fontFamily: root.fontFamily
          onChanged: function(v) { root.selectServer(parseInt(v, 10)) }
        }
        Dropdown {
          width: parent.width
          visible: !!root.form && !!root.formDetails
          label: root.t("approve.profile")
          value: root.form ? String(root.form.profileId) : ""
          options: root.formDetails ? root.formDetails.profiles.map(function(p) { return { value: String(p.id), label: p.name } }) : []
          foreground: root.foreground
          fontFamily: root.fontFamily
          onChanged: function(v) { root.setForm({ profileId: parseInt(v, 10) }) }
        }
        Dropdown {
          width: parent.width
          visible: !!root.form && !!root.formDetails
          label: root.t("approve.rootFolder")
          value: root.form ? root.form.rootFolder : ""
          options: root.formDetails ? root.formDetails.rootFolders.map(function(f) {
            var free = f.freeSpace >= 0 ? "  (" + root.t("approve.free").arg(Seerr.formatBytes(f.freeSpace, Commons.I18n.formatNumber)) + ")" : ""
            return { value: f.path, label: f.path + free }
          }) : []
          foreground: root.foreground
          fontFamily: root.fontFamily
          onChanged: function(v) { root.setForm({ rootFolder: v }) }
        }
        Dropdown {
          width: parent.width
          visible: !!root.form && !!root.formDetails && !!root.formDetails.languageProfiles && root.formDetails.languageProfiles.length > 0
          label: root.t("approve.languageProfile")
          value: root.form ? String(root.form.languageProfileId) : ""
          options: root.formDetails && root.formDetails.languageProfiles ? root.formDetails.languageProfiles.map(function(p) { return { value: String(p.id), label: p.name } }) : []
          foreground: root.foreground
          fontFamily: root.fontFamily
          onChanged: function(v) { root.setForm({ languageProfileId: parseInt(v, 10) }) }
        }

        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: !!root.form && !!root.formDetails && root.formDetails.tags.length > 0
          FieldLabel { text: root.t("approve.tags") }
          Flow {
            width: parent.width
            spacing: Style.space(5)
            Repeater {
              model: root.formDetails ? root.formDetails.tags : []
              Chip {
                required property var modelData
                label: modelData.name
                selected: !!root.form && root.form.tags.indexOf(modelData.id) !== -1
                onActivated: root.setForm({ tags: Seerr.toggleInList(root.form.tags, modelData.id) })
              }
            }
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: !!root.form && !!approveRoot.req && approveRoot.req.type === "tv"
          FieldLabel { text: root.t("approve.seasons") }
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
                onActivated: root.setForm({ seasons: Seerr.toggleInList(root.form.seasons, modelData.seasonNumber) })
              }
            }
          }
        }

        FlashLine { width: parent.width }

        Flow {
          width: parent.width
          spacing: Style.space(6)
          ActionButton {
            label: root.t("action.approve")
            glyph: root.gCheck
            primary: true
            busy: approveRoot.busy
            enabled: !!root.form && !root.formLoading && Seerr.formProblem(approveRoot.req, root.form) === ""
            tooltip: root.t("hint.shiftApprove")
            onActivated: function(mods) { root.submitForm((mods & Qt.ShiftModifier) !== 0) }
          }
          ActionButton {
            label: root.t("approve.quick")
            glyph: root.gBolt
            busy: approveRoot.busy
            visible: root.formError !== "" || !root.form
            onActivated: root.submitForm(true)
          }
          ActionButton {
            label: root.t("action.cancel")
            onActivated: root.back()
          }
        }
      }
    }
  }

  component SettingsPage: Item {
    id: settingsRoot
    implicitHeight: header0.implicitHeight + Style.space(10) + settingsColumn.implicitHeight


    function intervalLabel(sec) {
      return sec < 60 ? root.tn("settings.seconds", sec) : root.tn("settings.minutes", Math.round(sec / 60))
    }

    TopBar {
      id: header0
      width: parent.width
      title: root.t("settings.title")
      showBack: true
    }

    Flickable {
      anchors.top: header0.bottom
      anchors.topMargin: Style.space(10)
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
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

        FieldLabel { text: root.t("settings.url") }
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
          font.pixelSize: Style.font.caption
        }

        FieldLabel { text: root.t("settings.apiKey") }
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
            glyph: root.gLock
            enabled: keyField.text.trim() !== ""
            onActivated: {
              if (root.svc && root.svc.storeKey(keyField.text)) keyField.text = ""
              else root.flash(root.svc ? root.svc.keyMessage : "", true)
            }
          }
          ActionButton {
            label: root.t("action.remove")
            danger: true
            visible: !!root.svc && root.svc.keyState === "ok"
            onActivated: root.svc.clearKey()
          }
        }
        Hint {
          width: parent.width
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
            if (root.svc.keyState === "missing") return root.t("settings.noKey")
            if (!root.svc.baseUrl) return root.t("settings.noUrl")
            return ""
          }
          color: !!root.svc && (root.svc.connection === "error" || root.svc.keyMessage !== "" || (root.svc.connection === "connected" && !root.svc.canManage)) ? root.urgent : root.dim
        }

        FlashLine { width: parent.width }

        // -------- notifications
        PanelSeparator { foreground: root.foreground }
        PanelSectionHeader { text: root.t("settings.notifications"); foreground: root.foreground; fontFamily: root.fontFamily }
        SettingToggle { key: "notifyNewRequests"; label: root.t("settings.notifyNewRequests"); description: root.t("settings.notifyNewRequestsHelp") }
        SettingToggle { key: "notifyStatusChanges"; label: root.t("settings.notifyStatusChanges"); description: root.t("settings.notifyStatusChangesHelp") }
        SettingToggle { key: "notifyOnStartup"; label: root.t("settings.notifyOnStartup"); description: root.t("settings.notifyOnStartupHelp") }
        SettingToggle { key: "notifyPoster"; label: root.t("settings.notifyPoster"); description: root.t("settings.notifyPosterHelp") }
        SettingChoice {
          key: "notifyUrgency"
          label: root.t("settings.notifyUrgency")
          options: ["low", "normal", "critical"].map(function(v) { return { value: v, label: root.t("urgency." + v) } })
        }
        SettingChoice {
          key: "notifyGroupThreshold"
          numeric: true
          label: root.t("settings.notifyGroupThreshold")
          options: [1, 2, 3, 4, 5, 10, 20].map(function(v) { return { value: String(v), label: v === 1 ? root.t("settings.groupAlways") : root.tn("settings.groupFrom", v) } })
        }
        SettingChoice {
          key: "refreshIntervalSec"
          numeric: true
          label: root.t("settings.refreshInterval")
          options: [15, 30, 60, 120, 300, 600, 1800, 3600].map(function(v) { return { value: String(v), label: settingsRoot.intervalLabel(v) } })
        }

        // -------- defaults
        PanelSeparator { foreground: root.foreground }
        PanelSectionHeader { text: root.t("settings.defaults"); foreground: root.foreground; fontFamily: root.fontFamily }
        SettingChoice {
          key: "defaultFilter"
          label: root.t("settings.defaultFilter")
          options: Seerr.FILTERS.map(function(f) { return { value: f, label: root.t("filter." + f) } })
        }
        SettingChoice {
          key: "defaultMediaType"
          label: root.t("settings.defaultMediaType")
          options: Seerr.MEDIA_TYPES.map(function(f) { return { value: f, label: root.t("mediaType." + f) } })
        }
        SettingChoice {
          key: "defaultSort"
          label: root.t("settings.defaultSort")
          options: Seerr.SORTS.map(function(f) { return { value: f, label: root.t("sort." + f) } })
        }
        SettingChoice {
          key: "defaultSortDirection"
          label: root.t("settings.defaultSortDirection")
          options: Seerr.DIRECTIONS.map(function(f) { return { value: f, label: root.t("sort." + f) } })
        }
        SettingChoice {
          key: "pageSize"
          numeric: true
          label: root.t("settings.pageSize")
          options: [10, 20, 30, 50, 100].map(function(v) { return { value: String(v), label: String(v) } })
        }

        // -------- display
        PanelSeparator { foreground: root.foreground }
        PanelSectionHeader { text: root.t("settings.display"); foreground: root.foreground; fontFamily: root.fontFamily }
        SettingToggle { key: "showPosters"; label: root.t("settings.showPosters"); description: root.t("settings.showPostersHelp") }
        SettingToggle { key: "showBadge"; label: root.t("settings.showBadge") }
        SettingToggle { key: "badgeWhenEmpty"; label: root.t("settings.badgeWhenEmpty") }
        SettingToggle { key: "confirmDecline"; label: root.t("cfg.confirmDecline") }
      }
    }

  }

  component SettingToggle: Toggle {
    property string key: ""
    width: parent ? parent.width : 0
    checked: root.cfg[key] === true
    foreground: root.foreground
    fontFamily: root.fontFamily
    onClicked: {
      var patch = {}
      patch[key] = !checked
      root.saveSetting(patch)
    }
  }

  component SettingChoice: Dropdown {
    property string key: ""
    property bool numeric: false
    width: parent ? parent.width : 0
    value: String(root.cfg[key])
    foreground: root.foreground
    fontFamily: root.fontFamily
    onChanged: function(v) {
      var patch = {}
      patch[key] = numeric ? parseInt(v, 10) : v
      root.saveSetting(patch)
    }
  }

  // ================================================================ parts

  function longDate(ms) {
    if (!ms) return ""
    var d = new Date(ms)
    var loc = Qt.locale(Commons.I18n.formatLocale)
    return d.toLocaleDateString(loc, Locale.ShortFormat) + " " + d.toLocaleTimeString(loc, Locale.ShortFormat)
      + "  (" + relative(ms) + ")"
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

  component RequestRow: CursorSurface {
    id: row
    property var req: null
    property int rowIndex: 0
    readonly property var media: req && root.svc ? (root.svc.mediaRevision, root.svc.mediaFor(req)) : null
    readonly property string status: Seerr.statusKey(req)
    readonly property bool busy: !!req && !!root.svc && root.svc.isBusy(req.id)
    readonly property bool actionable: !!req && req.status === Seerr.REQUEST_PENDING && !!root.svc && !!root.svc && root.svc.canManage

    hasCursor: root.cursor === rowIndex
    foreground: root.foreground
    implicitHeight: Math.max(root.cfg.showPosters ? Style.space(54) : 0, rowContent.implicitHeight) + Style.space(10)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.cursor = row.rowIndex
      onClicked: root.openDetail(row.req)
    }

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(10)

      Poster {
        visible: root.cfg.showPosters
        Layout.preferredWidth: Style.space(36)
        Layout.preferredHeight: Style.space(54)
        Layout.alignment: Qt.AlignVCenter
        path: row.media ? row.media.posterPath : ""
        size: "w92"
        type: row.req ? row.req.type : "movie"
      }

      ColumnLayout {
        id: rowContent
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        spacing: Style.space(3)
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(6)
          PlainText {
            id: rowTitle
            Layout.fillWidth: true
            Layout.maximumWidth: rowTitle.implicitWidth
            text: row.req && root.svc ? root.svc.titleFor(row.req) : ""
            elide: Text.ElideRight
          }
          Tag {
            visible: !!row.req && row.req.is4k
            Layout.alignment: Qt.AlignVCenter
            text: "4K"
          }
          Item { Layout.fillWidth: true }
        }
        PlainText {
          Layout.fillWidth: true
          color: root.dim
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          text: {
            var r = row.req
            if (!r) return ""
            var parts = [(r.type === "tv" ? root.gTv + " " + root.t("type.tv") : root.gMovie + " " + root.t("type.movie"))]
            if (r.type === "tv" && r.seasons.length) parts.push(root.t("detail.seasonsShort").arg(Seerr.seasonsLabel(r.seasons)))
            if (r.requestedBy) parts.push(r.requestedBy.name)
            parts.push(root.relative(root.svc && root.svc.view.sort === "modified" ? r.updatedAt : r.createdAt))
            return parts.join(" · ")
          }
        }
      }

      StatusBadge {
        visible: !row.actionable
        Layout.alignment: Qt.AlignVCenter
        status: row.status
      }
      IconButton {
        visible: row.actionable
        Layout.alignment: Qt.AlignVCenter
        glyph: root.gCheck
        color: root.accent
        busy: row.busy
        tooltip: root.t("action.approve") + "  (a)\n" + root.t("hint.shiftApprove")
        onActivated: function(mods) { root.approve(row.req, (mods & Qt.ShiftModifier) !== 0) }
      }
      IconButton {
        visible: row.actionable
        Layout.alignment: Qt.AlignVCenter
        glyph: root.gClose
        color: root.urgent
        busy: row.busy
        tooltip: root.t("action.decline") + "  (d)"
        onActivated: root.decline(row.req)
      }
    }
  }

  component TopBar: RowLayout {
    id: topBar
    property string title: ""
    property string subtitle: ""
    property bool subtitleUrgent: false
    property bool showBack: false
    default property alias actions: actionRow.data
    spacing: Style.space(8)

    IconButton {
      visible: topBar.showBack
      glyph: root.gBack
      tooltip: root.t("action.back") + "  (Esc)"
      Layout.alignment: Qt.AlignVCenter
      onActivated: root.back()
    }
    PlainText {
      visible: !topBar.showBack
      text: root.gSeerr
      font.pixelSize: Style.font.display
      Layout.alignment: Qt.AlignVCenter
    }
    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.space(1)
      PlainText {
        Layout.fillWidth: true
        text: topBar.title
        font.pixelSize: Style.font.title
        font.bold: true
        elide: Text.ElideRight
      }
      PlainText {
        Layout.fillWidth: true
        visible: text !== ""
        text: topBar.subtitle
        color: topBar.subtitleUrgent ? root.urgent : root.dim
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }
    Row {
      id: actionRow
      spacing: Style.space(2)
      Layout.alignment: Qt.AlignVCenter
    }
  }

  component Poster: Rectangle {
    id: poster
    property string path: ""
    property string size: "w92"
    property string type: "movie"
    readonly property string url: root.cfg.showPosters ? Seerr.posterUrl(path, size) : ""
    color: Util.alpha(root.foreground, 0.06)
    radius: Style.cornerRadius
    clip: true
    PlainText {
      anchors.centerIn: parent
      visible: image.status !== Image.Ready
      text: poster.type === "tv" ? root.gTv : root.gMovie
      color: root.dim
      font.pixelSize: Math.round(poster.width * 0.4)
    }
    Image {
      id: image
      anchors.fill: parent
      source: poster.url
      asynchronous: true
      cache: true
      fillMode: Image.PreserveAspectCrop
      sourceSize.width: poster.width * 2
      sourceSize.height: poster.height * 2
      opacity: status === Image.Ready ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic } }
    }
  }

  component StatusBadge: Rectangle {
    id: badge
    property string status: "unknown"
    readonly property color tone: root.statusColor(status)
    implicitWidth: badgeLabel.implicitWidth + Style.space(12)
    implicitHeight: badgeLabel.implicitHeight + Style.space(4)
    radius: height / 2
    color: Util.alpha(tone, 0.14)
    border.width: 1
    border.color: Util.alpha(tone, 0.5)
    PlainText {
      id: badgeLabel
      anchors.centerIn: parent
      text: root.t("status." + badge.status)
      color: badge.tone
      font.pixelSize: Style.font.caption
    }
  }

  component Tag: Rectangle {
    property alias text: tagLabel.text
    implicitWidth: tagLabel.implicitWidth + Style.space(8)
    implicitHeight: tagLabel.implicitHeight + Style.space(2)
    radius: Style.space(3)
    color: "transparent"
    border.width: 1
    border.color: root.dim
    PlainText {
      id: tagLabel
      anchors.centerIn: parent
      color: root.dim
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }

  component Chip: Rectangle {
    id: chip
    property string label: ""
    property string tooltip: ""
    property bool selected: false
    signal activated()
    implicitWidth: chipLabel.implicitWidth + Style.space(16)
    implicitHeight: chipLabel.implicitHeight + Style.space(8)
    radius: height / 2
    color: selected ? Util.alpha(root.accent, 0.2) : (chipMouse.containsMouse ? Style.hoverFillFor(root.foreground, root.accent) : "transparent")
    border.width: 1
    border.color: selected ? root.accent : Util.alpha(root.foreground, 0.3)
    PlainText {
      id: chipLabel
      anchors.centerIn: parent
      text: (chip.selected ? root.gCheck + " " : "") + chip.label
      color: chip.selected ? root.accent : root.foreground
      font.pixelSize: Style.font.bodySmall
    }
    MouseArea {
      id: chipMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: chip.activated()
    }
    PanelToolTip { visible: chipMouse.containsMouse && chip.tooltip !== ""; text: chip.tooltip; fontFamily: root.fontFamily }
  }

  // A glyph button that reports the modifiers held, so Shift+click can mean
  // "approve with defaults".
  component IconButton: Item {
    id: ib
    property string glyph: ""
    property string tooltip: ""
    property color color: root.foreground
    property bool busy: false
    signal activated(int modifiers)
    implicitWidth: Style.space(26)
    implicitHeight: Style.space(26)
    opacity: enabled ? (busy ? 0.45 : 1) : 0.35
    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: ibMouse.containsMouse && ib.enabled && !ib.busy ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
    }
    PlainText {
      anchors.centerIn: parent
      text: ib.glyph
      color: ib.color
      font.pixelSize: Style.font.icon
    }
    MouseArea {
      id: ibMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: ib.enabled && !ib.busy ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: function(mouse) { if (ib.enabled && !ib.busy) ib.activated(mouse.modifiers) }
    }
    PanelToolTip { visible: ibMouse.containsMouse && ib.tooltip !== ""; text: ib.tooltip; fontFamily: root.fontFamily }
  }

  component ActionButton: Rectangle {
    id: ab
    property string label: ""
    property string glyph: ""
    property string tooltip: ""
    property bool primary: false
    property bool danger: false
    property bool busy: false
    signal activated(int modifiers)
    readonly property color tone: danger ? root.urgent : (primary ? root.accent : root.foreground)
    implicitWidth: abRow.implicitWidth + Style.space(20)
    implicitHeight: Style.spacing.controlHeight
    radius: Style.cornerRadius
    opacity: enabled ? (busy ? 0.5 : 1) : 0.4
    color: abMouse.containsMouse && enabled && !busy ? Util.alpha(tone, 0.18) : (primary ? Util.alpha(tone, 0.1) : "transparent")
    border.width: 1
    border.color: Util.alpha(tone, primary || danger ? 0.7 : 0.35)
    Row {
      id: abRow
      anchors.centerIn: parent
      spacing: Style.space(6)
      PlainText { visible: ab.glyph !== ""; text: ab.glyph; color: ab.tone; font.pixelSize: Style.font.icon; anchors.verticalCenter: parent.verticalCenter }
      PlainText { text: ab.busy ? "…" : ab.label; color: ab.tone; anchors.verticalCenter: parent.verticalCenter }
    }
    MouseArea {
      id: abMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: ab.enabled && !ab.busy ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: function(mouse) { if (ab.enabled && !ab.busy) ab.activated(mouse.modifiers) }
    }
    PanelToolTip { visible: abMouse.containsMouse && ab.tooltip !== ""; text: ab.tooltip; fontFamily: root.fontFamily }
  }

  component InfoPair: RowLayout {
    id: pair
    property string label: ""
    property string value: ""
    width: parent ? parent.width : 0
    spacing: Style.space(8)
    PlainText { text: pair.label; color: root.dim; font.pixelSize: Style.font.bodySmall }
    PlainText {
      Layout.fillWidth: true
      horizontalAlignment: Text.AlignRight
      text: pair.value
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }
  }

  component FlashLine: PlainText {
    visible: root.flashText !== ""
    text: root.flashText
    color: root.flashError ? root.urgent : root.dim
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.WordWrap
  }

  component FieldLabel: PlainText {
    color: root.dim
    font.pixelSize: Style.font.bodySmall
  }

  component Hint: PlainText {
    color: root.dim
    font.pixelSize: Style.font.bodySmall
    wrapMode: Text.WordWrap
  }

  // Every string this panel shows may come from Seerr: never rich text.
  component PlainText: Text {
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }
}
