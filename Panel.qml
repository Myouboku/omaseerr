import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "model/requests.js" as Requests
import "model/settings.js" as Settings
import "pages"
import "panel"
import "ui"
import "ui/Glyphs.js" as Glyphs

// The bar icon and its panel. One of these exists per monitor; shared state
// and network traffic live in Service.qml, which every copy shares. This file
// wires the parts: per-panel state, approval form and keys (panel/), the
// pages (pages/), which take this panel as their `ctx`, and the display
// components (ui/).
Panel {
  id: root
  moduleName: Settings.PLUGIN_ID
  ipcTarget: Settings.PLUGIN_ID
  // The service answers IPC once for all monitors.
  manageIpc: false

  // ---------------------------------------------------------------- service

  property var svc: null

  function resolveService() {
    if (svc) return
    var api = bar && bar.shell ? bar.shell : null
    if (api && typeof api.serviceFor === "function") svc = api.serviceFor(Settings.PLUGIN_ID)
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
    var c = Requests.statusColor(key)
    if (c === "") return foreground
    if (c === "dim") return dim
    return c
  }

  readonly property var cfg: svc ? svc.settings : Settings.normalizeSettings({})
  readonly property bool connected: !!svc && svc.connection === "connected"
  readonly property int pending: svc ? svc.counts.pending : 0

  // Seerr stopped answering after it had: what is shown is from before.
  readonly property bool offline: !!svc && (svc.connection === "error" || (svc.connection === "connecting" && svc.lastError !== ""))
  readonly property bool retrying: !!svc && svc.connection === "connecting" && svc.lastError !== ""

  // ---------------------------------------------------------------- state

  // What the panel shows and does: page, cursor, toast, confirmation and
  // the actions behind keys and buttons.
  readonly property PanelState nav: PanelState { ctx: root }
  // The approval form's servers, options and choices.
  readonly property ApprovalForm approval: ApprovalForm { ctx: root }
  // The keys, turned into calls on the two above.
  readonly property Keyboard keyboard: Keyboard { ctx: root }

  // The panel's content (built when first opened): the pages, the toast and
  // the confirmation dialog.
  readonly property Item content: panel.loadedContent

  // ---------------------------------------------------------------- lifecycle

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: opened ? nav.opening() : nav.closing()

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
        if (root.nav.page === "detail") return detailPage.implicitHeight
        if (root.nav.page === "approve") return approvePage.implicitHeight
        if (root.nav.page === "settings") return settingsPage.implicitHeight
        return listPage.implicitHeight
      }
      // On the list, Tab comes back here after the filters and the search.
      activeFocusOnTab: root.nav.page === "list"
      Keys.onPressed: function(event) { root.keyboard.handleKey(event) }
      readonly property Item focusedItem: Window.activeFocusItem
      onFocusedItemChanged: Qt.callLater(function() { root.nav.revealFocus(body.focusedItem) })

      ListPage { id: listPage; ctx: root; anchors.fill: parent; visible: root.nav.page === "list"; FadeIn on opacity {} }
      DetailPage { id: detailPage; ctx: root; anchors.fill: parent; visible: root.nav.page === "detail"; FadeIn on opacity {} }
      ApprovePage { id: approvePage; ctx: root; anchors.fill: parent; visible: root.nav.page === "approve"; FadeIn on opacity {} }
      SettingsPage { id: settingsPage; ctx: root; anchors.fill: parent; visible: root.nav.page === "settings"; FadeIn on opacity {} }

      Toast {
        z: 5
        message: root.nav.flashText
        isError: root.nav.flashError
        serial: root.nav.flashSerial
        foreground: root.foreground
        success: root.statusColor("available")
        urgent: root.urgent
        fontFamily: root.fontFamily
      }

      ConfirmDialog {
        id: confirmDialog
        anchors.fill: parent
        z: 10
        opened: root.nav.confirmOpen
        // Each question starts on its action, whatever was picked last time.
        onOpenedChanged: if (opened) selectedIndex = 1
        message: root.nav.confirmAction === "delete" ? root.t("confirm.delete") : root.t("confirm.decline")
        confirmText: root.nav.confirmAction === "delete" ? root.t("action.delete") : root.t("action.decline")
        cancelText: root.t("action.cancel")
        foreground: root.foreground
        fontFamily: root.fontFamily
        onCanceled: root.nav.confirmOpen = false
        onConfirmed: root.nav.confirmYes()
      }
    }
  }
}
