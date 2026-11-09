import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../model/Seerr.js" as Seerr
import "../ui"
import "../ui/Glyphs.js" as Glyphs

// The plugin's settings, saved to shell.json through the service.
Item {
  id: settingsRoot
  // The panel: state, actions, service, settings, translations and theme.
  required property var ctx
  implicitHeight: header0.implicitHeight + Style.space(10) + settingsColumn.implicitHeight
                  + settingsKeys.topMargin + settingsKeys.implicitHeight


  function intervalLabel(sec) {
    return sec < 60 ? ctx.tn("settings.seconds", sec) : ctx.tn("settings.minutes", Math.round(sec / 60))
  }

  TopBar {
    id: header0
    width: parent.width
    title: ctx.t("settings.title")
    showBack: true
    backTooltip: ctx.t("action.back") + "  (Esc)"
    foreground: ctx.foreground; dim: ctx.dim; accent: ctx.accent; urgent: ctx.urgent; fontFamily: ctx.fontFamily
    onBack: ctx.back()
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
      PanelSectionHeader { text: ctx.t("settings.connection"); foreground: ctx.foreground; fontFamily: ctx.fontFamily }

      FieldLabel { text: ctx.t("settings.url"); color: ctx.dim; font.family: ctx.fontFamily }
      RowLayout {
        width: parent.width
        spacing: Style.space(6)
        TextField {
          id: urlField
          Layout.fillWidth: true
          text: ctx.cfg.url
          placeholderText: "https://seerr.example.com"
          foreground: ctx.foreground
          font.family: ctx.fontFamily
          font.pixelSize: Style.font.body
          inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase
          onAccepted: saveUrl.activated(0)
        }
        ActionButton {
          id: saveUrl
          label: ctx.t("action.save")
          enabled: urlField.text.trim() !== ctx.cfg.url
          foreground: ctx.foreground; accent: ctx.accent; urgent: ctx.urgent; fontFamily: ctx.fontFamily
          onActivated: {
            var n = Seerr.normalizeBaseUrl(urlField.text)
            if (urlField.text.trim() === "") { ctx.saveSetting({ url: "" }); return }
            if (!n.ok) { ctx.flash(ctx.t("settings.urlInvalid"), true); return }
            urlField.text = n.url
            ctx.saveSetting({ url: n.url })
          }
        }
      }
      Hint {
        width: parent.width
        visible: !!ctx.svc && ctx.svc.exposed
        text: ctx.t("settings.httpWarning")
        color: ctx.urgent
        font.family: ctx.fontFamily
        font.pixelSize: Style.font.caption
      }

      FieldLabel { text: ctx.t("settings.apiKey"); color: ctx.dim; font.family: ctx.fontFamily }
      RowLayout {
        width: parent.width
        spacing: Style.space(6)
        TextField {
          id: keyField
          Layout.fillWidth: true
          password: true
          placeholderText: ctx.svc && ctx.svc.keyState === "ok" ? ctx.t("settings.keyStored") : ctx.t("settings.keyPlaceholder")
          foreground: ctx.foreground
          font.family: ctx.fontFamily
          font.pixelSize: Style.font.body
          inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
          onAccepted: saveKey.activated(0)
        }
        ActionButton {
          id: saveKey
          label: ctx.t("action.save")
          glyph: Glyphs.lock
          enabled: keyField.text.trim() !== ""
          foreground: ctx.foreground; accent: ctx.accent; urgent: ctx.urgent; fontFamily: ctx.fontFamily
          onActivated: {
            if (ctx.svc && ctx.svc.storeKey(keyField.text)) keyField.text = ""
            else ctx.flash(ctx.svc ? ctx.svc.keyMessage : "", true)
          }
        }
        // Rarely used: kept plain rather than alarming red.
        ActionButton {
          label: ctx.t("action.remove")
          visible: !!ctx.svc && ctx.svc.keyState === "ok"
          foreground: ctx.foreground; accent: ctx.accent; urgent: ctx.urgent; fontFamily: ctx.fontFamily
          onActivated: ctx.svc.clearKey()
        }
      }
      Hint {
        width: parent.width
        color: ctx.dim
        font.family: ctx.fontFamily
        font.pixelSize: Style.font.caption
        text: ctx.t("settings.keyHelp")
      }
      Hint {
        width: parent.width
        text: {
          if (!ctx.svc) return ""
          if (ctx.svc.keyMessage) return ctx.svc.keyMessage
          if (ctx.svc.connection === "connected")
            return ctx.t("settings.connectedAs").arg(ctx.svc.me ? ctx.svc.me.name : "?")
              + (ctx.svc.canManage ? "" : "  —  " + ctx.t("settings.noManage"))
          if (ctx.svc.connection === "connecting") return ctx.t("bar.connecting")
          if (ctx.svc.connection === "error") return ctx.svc.lastError
          if (!ctx.svc.baseUrl) return ctx.t("settings.noUrl")
          if (ctx.svc.keyState === "missing") return ctx.t("settings.noKey")
          return ""
        }
        color: !!ctx.svc && (ctx.svc.connection === "error" || ctx.svc.keyMessage !== "" || (ctx.svc.connection === "connected" && !ctx.svc.canManage)) ? ctx.urgent : ctx.dim
        font.family: ctx.fontFamily
      }

      BoundChoice {
        key: "refreshIntervalSec"
        numeric: true
        label: ctx.t("settings.refreshInterval")
        options: [15, 30, 60, 120, 300, 600, 1800, 3600].map(function(v) { return { value: String(v), label: settingsRoot.intervalLabel(v) } })
      }

      // -------- notifications
      PanelSeparator { foreground: ctx.foreground }
      PanelSectionHeader { text: ctx.t("settings.notifications"); foreground: ctx.foreground; fontFamily: ctx.fontFamily }
      BoundToggle { key: "notifyNewRequests"; label: ctx.t("settings.notifyNewRequests"); description: ctx.t("settings.notifyNewRequestsHelp") }
      BoundToggle { key: "notifyStatusChanges"; label: ctx.t("settings.notifyStatusChanges"); description: ctx.t("settings.notifyStatusChangesHelp") }
      BoundToggle { key: "notifyPoster"; label: ctx.t("settings.notifyPoster"); description: ctx.t("settings.notifyPosterHelp") }
      BoundChoice {
        key: "notifyUrgency"
        label: ctx.t("settings.notifyUrgency")
        options: ["low", "normal", "critical"].map(function(v) { return { value: v, label: ctx.t("urgency." + v) } })
      }
      BoundChoice {
        key: "notifyGroupThreshold"
        numeric: true
        label: ctx.t("settings.notifyGroupThreshold")
        options: [1, 2, 3, 4, 5, 10, 20].map(function(v) { return { value: String(v), label: v === 1 ? ctx.t("settings.groupAlways") : ctx.tn("settings.groupFrom", v) } })
      }

      // -------- defaults
      PanelSeparator { foreground: ctx.foreground }
      PanelSectionHeader { text: ctx.t("settings.defaults"); foreground: ctx.foreground; fontFamily: ctx.fontFamily }
      BoundChoice {
        key: "defaultFilter"
        label: ctx.t("settings.defaultFilter")
        options: Seerr.FILTERS.map(function(f) { return { value: f, label: ctx.t("filter." + f) } })
      }
      BoundChoice {
        key: "defaultMediaType"
        label: ctx.t("settings.defaultMediaType")
        options: Seerr.MEDIA_TYPES.map(function(f) { return { value: f, label: ctx.t("mediaType." + f) } })
      }
      BoundChoice {
        key: "defaultSort"
        label: ctx.t("settings.defaultSort")
        options: Seerr.SORTS.map(function(f) { return { value: f, label: ctx.t("sort." + f) } })
      }
      BoundChoice {
        key: "defaultSortDirection"
        label: ctx.t("settings.defaultSortDirection")
        options: Seerr.DIRECTIONS.map(function(f) { return { value: f, label: ctx.t("sort." + f) } })
      }
      BoundChoice {
        key: "pageSize"
        numeric: true
        label: ctx.t("settings.pageSize")
        options: [10, 20, 30, 50, 100].map(function(v) { return { value: String(v), label: String(v) } })
      }

      // -------- display
      PanelSeparator { foreground: ctx.foreground }
      PanelSectionHeader { text: ctx.t("settings.display"); foreground: ctx.foreground; fontFamily: ctx.fontFamily }
      BoundToggle { key: "showPosters"; label: ctx.t("settings.showPosters"); description: ctx.t("settings.showPostersHelp") }
      BoundToggle { key: "confirmDecline"; label: ctx.t("settings.confirmDecline") }
    }
  }

  // Pinned below the settings.
  KeyHints {
    id: settingsKeys
    readonly property real topMargin: Style.space(10)
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    text: ctx.t("settings.keys")
    tone: ctx.dim
    fontFamily: ctx.fontFamily
  }

  // The settings page's controls, bound to the panel's settings and theme.
  component BoundToggle: SettingToggle {
    values: settingsRoot.ctx.cfg
    foreground: settingsRoot.ctx.foreground
    fontFamily: settingsRoot.ctx.fontFamily
    onSave: function(patch) { settingsRoot.ctx.saveSetting(patch) }
  }

  component BoundChoice: SettingChoice {
    values: settingsRoot.ctx.cfg
    foreground: settingsRoot.ctx.foreground
    fontFamily: settingsRoot.ctx.fontFamily
    onSave: function(patch) { settingsRoot.ctx.saveSetting(patch) }
  }
}
