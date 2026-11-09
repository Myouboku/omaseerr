import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../model/api.js" as Api
import "../model/form.js" as Form
import "../ui"
import "../ui/Glyphs.js" as Glyphs

// The approval form: server, profile, root folder, language, tags, seasons.
Item {
  id: approveRoot
  // The panel: state, actions, service, settings, translations and theme.
  required property var ctx
  readonly property var req: ctx.approval.req
  readonly property bool busy: !!req && !!ctx.svc && ctx.svc.isBusy(req.id)
  implicitHeight: header0.implicitHeight + Style.space(10) + formColumn.implicitHeight
                  + approveKeys.topMargin + approveKeys.implicitHeight

  TopBar {
    id: header0
    width: parent.width
    title: ctx.t("approve.title")
    showBack: true
    backTooltip: ctx.t("action.back") + "  (Esc)"
    foreground: ctx.foreground; dim: ctx.dim; accent: ctx.accent; urgent: ctx.urgent; fontFamily: ctx.fontFamily
    onBack: ctx.nav.back()
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
          visible: ctx.cfg.showPosters
          Layout.preferredWidth: Style.space(36)
          Layout.preferredHeight: Style.space(54)
          url: ctx.cfg.showPosters ? Api.posterUrl(ctx.approval.media ? ctx.approval.media.posterPath : "", "w92") : ""
          type: approveRoot.req ? approveRoot.req.type : "movie"
          foreground: ctx.foreground; dim: ctx.dim; fontFamily: ctx.fontFamily
        }
        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(3)
          PlainText {
            Layout.fillWidth: true
            text: approveRoot.req && ctx.svc ? ctx.svc.titleFor(approveRoot.req) : ""
            color: ctx.foreground
            font.family: ctx.fontFamily
            font.bold: true
            elide: Text.ElideRight
          }
          PlainText {
            Layout.fillWidth: true
            color: ctx.dim
            font.family: ctx.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            text: {
              var r = approveRoot.req
              if (!r) return ""
              var parts = [r.type === "tv" ? ctx.t("type.tv") : ctx.t("type.movie")]
              if (r.is4k) parts.push("4K")
              if (r.requestedBy) parts.push(ctx.t("notify.by").arg(r.requestedBy.name))
              return parts.join(" · ")
            }
          }
        }
      }

      Hint {
        width: parent.width
        visible: ctx.approval.loading
        text: ctx.t("approve.loading")
        color: ctx.dim
        font.family: ctx.fontFamily
      }
      Hint {
        width: parent.width
        visible: ctx.approval.error !== ""
        text: ctx.approval.error
        color: ctx.urgent
        font.family: ctx.fontFamily
      }

      SyncedDropdown {
        width: parent.width
        visible: ctx.approval.servers.length > 0 && !!ctx.approval.form
        label: approveRoot.req && approveRoot.req.type === "tv" ? ctx.t("approve.sonarr") : ctx.t("approve.radarr")
        current: ctx.approval.form ? String(ctx.approval.form.serverId) : ""
        options: ctx.approval.servers.map(function(s) { return { value: String(s.id), label: s.isDefault ? ctx.t("approve.defaultServer").arg(s.name) : s.name } })
        foreground: ctx.foreground
        fontFamily: ctx.fontFamily
        onChanged: function(v) { ctx.approval.selectServer(parseInt(v, 10)) }
      }
      SyncedDropdown {
        width: parent.width
        visible: !!ctx.approval.form && !!ctx.approval.details
        label: ctx.t("approve.profile")
        current: ctx.approval.form ? String(ctx.approval.form.profileId) : ""
        options: ctx.approval.details ? ctx.approval.details.profiles.map(function(p) { return { value: String(p.id), label: p.name } }) : []
        foreground: ctx.foreground
        fontFamily: ctx.fontFamily
        onChanged: function(v) { ctx.approval.set({ profileId: parseInt(v, 10) }) }
      }
      SyncedDropdown {
        width: parent.width
        visible: !!ctx.approval.form && !!ctx.approval.details
        label: ctx.t("approve.rootFolder")
        current: ctx.approval.form ? ctx.approval.form.rootFolder : ""
        options: ctx.approval.details ? ctx.approval.details.rootFolders.map(function(f) {
          var free = f.freeSpace >= 0 ? "  (" + ctx.t("approve.free").arg(Form.formatBytes(f.freeSpace, Commons.I18n.formatNumber)) + ")" : ""
          return { value: f.path, label: f.path + free }
        }) : []
        foreground: ctx.foreground
        fontFamily: ctx.fontFamily
        onChanged: function(v) { ctx.approval.set({ rootFolder: v }) }
      }
      SyncedDropdown {
        width: parent.width
        visible: !!ctx.approval.form && !!ctx.approval.details && !!ctx.approval.details.languageProfiles && ctx.approval.details.languageProfiles.length > 0
        label: ctx.t("approve.languageProfile")
        current: ctx.approval.form ? String(ctx.approval.form.languageProfileId) : ""
        options: ctx.approval.details && ctx.approval.details.languageProfiles ? ctx.approval.details.languageProfiles.map(function(p) { return { value: String(p.id), label: p.name } }) : []
        foreground: ctx.foreground
        fontFamily: ctx.fontFamily
        onChanged: function(v) { ctx.approval.set({ languageProfileId: parseInt(v, 10) }) }
      }

      Column {
        width: parent.width
        spacing: Style.space(6)
        visible: !!ctx.approval.form && !!ctx.approval.details && ctx.approval.details.tags.length > 0
        FieldLabel { text: ctx.t("approve.tags"); color: ctx.dim; font.family: ctx.fontFamily }
        Flow {
          width: parent.width
          spacing: Style.space(5)
          Repeater {
            model: ctx.approval.details ? ctx.approval.details.tags : []
            Chip {
              required property var modelData
              label: modelData.name
              selected: !!ctx.approval.form && ctx.approval.form.tags.indexOf(modelData.id) !== -1
              foreground: ctx.foreground; accent: ctx.accent; fontFamily: ctx.fontFamily
              onActivated: ctx.approval.set({ tags: Form.toggleInList(ctx.approval.form.tags, modelData.id) })
            }
          }
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(6)
        visible: !!ctx.approval.form && !!approveRoot.req && approveRoot.req.type === "tv"
        FieldLabel { text: ctx.t("approve.seasons"); color: ctx.dim; font.family: ctx.fontFamily }
        Flow {
          width: parent.width
          spacing: Style.space(5)
          Repeater {
            model: {
              var m = ctx.approval.media
              var list = m && m.seasons.length ? m.seasons.filter(function(s) { return s.seasonNumber > 0 }) : []
              if (list.length === 0 && approveRoot.req) list = approveRoot.req.seasons.map(function(n) { return { seasonNumber: n, episodeCount: 0 } })
              return list
            }
            Chip {
              required property var modelData
              label: ctx.t("approve.season").arg(modelData.seasonNumber)
              tooltip: modelData.episodeCount ? ctx.tn("approve.episodes", modelData.episodeCount) : ""
              selected: !!ctx.approval.form && ctx.approval.form.seasons.indexOf(modelData.seasonNumber) !== -1
              foreground: ctx.foreground; accent: ctx.accent; fontFamily: ctx.fontFamily
              onActivated: ctx.approval.set({ seasons: Form.toggleInList(ctx.approval.form.seasons, modelData.seasonNumber) })
            }
          }
        }
      }

      Flow {
        width: parent.width
        spacing: Style.space(6)
        ActionButton {
          label: ctx.t("action.approve")
          glyph: Glyphs.check
          primary: true
          busy: approveRoot.busy
          enabled: !!ctx.approval.form && !ctx.approval.loading && Form.formProblem(approveRoot.req, ctx.approval.form) === ""
          tooltip: ctx.t("hint.shiftApprove")
          foreground: ctx.foreground; accent: ctx.accent; urgent: ctx.urgent; fontFamily: ctx.fontFamily
          onActivated: function(mods) { ctx.approval.submit((mods & Qt.ShiftModifier) !== 0) }
        }
        ActionButton {
          label: ctx.t("approve.quick")
          glyph: Glyphs.bolt
          busy: approveRoot.busy
          visible: ctx.approval.error !== "" || !ctx.approval.form
          foreground: ctx.foreground; accent: ctx.accent; urgent: ctx.urgent; fontFamily: ctx.fontFamily
          onActivated: ctx.approval.submit(true)
        }
        ActionButton {
          label: ctx.t("action.cancel")
          foreground: ctx.foreground; accent: ctx.accent; urgent: ctx.urgent; fontFamily: ctx.fontFamily
          onActivated: ctx.nav.back()
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
    text: ctx.t("approve.keys")
    tone: ctx.dim
    fontFamily: ctx.fontFamily
  }
}
