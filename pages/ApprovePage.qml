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

// The approval form: server, profile, root folder, language, tags, seasons.
Item {
  id: approveRoot
  // The panel: state, actions, service, settings, translations and theme.
  required property var ctx
  readonly property var req: ctx.formReq
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
    onBack: ctx.back()
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
          url: ctx.cfg.showPosters ? Seerr.posterUrl(ctx.formMedia ? ctx.formMedia.posterPath : "", "w92") : ""
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
        visible: ctx.formLoading
        text: ctx.t("approve.loading")
        color: ctx.dim
        font.family: ctx.fontFamily
      }
      Hint {
        width: parent.width
        visible: ctx.formError !== ""
        text: ctx.formError
        color: ctx.urgent
        font.family: ctx.fontFamily
      }

      SyncedDropdown {
        width: parent.width
        visible: ctx.formServers.length > 0 && !!ctx.form
        label: approveRoot.req && approveRoot.req.type === "tv" ? ctx.t("approve.sonarr") : ctx.t("approve.radarr")
        current: ctx.form ? String(ctx.form.serverId) : ""
        options: ctx.formServers.map(function(s) { return { value: String(s.id), label: s.isDefault ? ctx.t("approve.defaultServer").arg(s.name) : s.name } })
        foreground: ctx.foreground
        fontFamily: ctx.fontFamily
        onChanged: function(v) { ctx.selectServer(parseInt(v, 10)) }
      }
      SyncedDropdown {
        width: parent.width
        visible: !!ctx.form && !!ctx.formDetails
        label: ctx.t("approve.profile")
        current: ctx.form ? String(ctx.form.profileId) : ""
        options: ctx.formDetails ? ctx.formDetails.profiles.map(function(p) { return { value: String(p.id), label: p.name } }) : []
        foreground: ctx.foreground
        fontFamily: ctx.fontFamily
        onChanged: function(v) { ctx.setForm({ profileId: parseInt(v, 10) }) }
      }
      SyncedDropdown {
        width: parent.width
        visible: !!ctx.form && !!ctx.formDetails
        label: ctx.t("approve.rootFolder")
        current: ctx.form ? ctx.form.rootFolder : ""
        options: ctx.formDetails ? ctx.formDetails.rootFolders.map(function(f) {
          var free = f.freeSpace >= 0 ? "  (" + ctx.t("approve.free").arg(Seerr.formatBytes(f.freeSpace, Commons.I18n.formatNumber)) + ")" : ""
          return { value: f.path, label: f.path + free }
        }) : []
        foreground: ctx.foreground
        fontFamily: ctx.fontFamily
        onChanged: function(v) { ctx.setForm({ rootFolder: v }) }
      }
      SyncedDropdown {
        width: parent.width
        visible: !!ctx.form && !!ctx.formDetails && !!ctx.formDetails.languageProfiles && ctx.formDetails.languageProfiles.length > 0
        label: ctx.t("approve.languageProfile")
        current: ctx.form ? String(ctx.form.languageProfileId) : ""
        options: ctx.formDetails && ctx.formDetails.languageProfiles ? ctx.formDetails.languageProfiles.map(function(p) { return { value: String(p.id), label: p.name } }) : []
        foreground: ctx.foreground
        fontFamily: ctx.fontFamily
        onChanged: function(v) { ctx.setForm({ languageProfileId: parseInt(v, 10) }) }
      }

      Column {
        width: parent.width
        spacing: Style.space(6)
        visible: !!ctx.form && !!ctx.formDetails && ctx.formDetails.tags.length > 0
        FieldLabel { text: ctx.t("approve.tags"); color: ctx.dim; font.family: ctx.fontFamily }
        Flow {
          width: parent.width
          spacing: Style.space(5)
          Repeater {
            model: ctx.formDetails ? ctx.formDetails.tags : []
            Chip {
              required property var modelData
              label: modelData.name
              selected: !!ctx.form && ctx.form.tags.indexOf(modelData.id) !== -1
              foreground: ctx.foreground; accent: ctx.accent; fontFamily: ctx.fontFamily
              onActivated: ctx.setForm({ tags: Seerr.toggleInList(ctx.form.tags, modelData.id) })
            }
          }
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(6)
        visible: !!ctx.form && !!approveRoot.req && approveRoot.req.type === "tv"
        FieldLabel { text: ctx.t("approve.seasons"); color: ctx.dim; font.family: ctx.fontFamily }
        Flow {
          width: parent.width
          spacing: Style.space(5)
          Repeater {
            model: {
              var m = ctx.formMedia
              var list = m && m.seasons.length ? m.seasons.filter(function(s) { return s.seasonNumber > 0 }) : []
              if (list.length === 0 && approveRoot.req) list = approveRoot.req.seasons.map(function(n) { return { seasonNumber: n, episodeCount: 0 } })
              return list
            }
            Chip {
              required property var modelData
              label: ctx.t("approve.season").arg(modelData.seasonNumber)
              tooltip: modelData.episodeCount ? ctx.tn("approve.episodes", modelData.episodeCount) : ""
              selected: !!ctx.form && ctx.form.seasons.indexOf(modelData.seasonNumber) !== -1
              foreground: ctx.foreground; accent: ctx.accent; fontFamily: ctx.fontFamily
              onActivated: ctx.setForm({ seasons: Seerr.toggleInList(ctx.form.seasons, modelData.seasonNumber) })
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
          enabled: !!ctx.form && !ctx.formLoading && Seerr.formProblem(approveRoot.req, ctx.form) === ""
          tooltip: ctx.t("hint.shiftApprove")
          foreground: ctx.foreground; accent: ctx.accent; urgent: ctx.urgent; fontFamily: ctx.fontFamily
          onActivated: function(mods) { ctx.submitForm((mods & Qt.ShiftModifier) !== 0) }
        }
        ActionButton {
          label: ctx.t("approve.quick")
          glyph: Glyphs.bolt
          busy: approveRoot.busy
          visible: ctx.formError !== "" || !ctx.form
          foreground: ctx.foreground; accent: ctx.accent; urgent: ctx.urgent; fontFamily: ctx.fontFamily
          onActivated: ctx.submitForm(true)
        }
        ActionButton {
          label: ctx.t("action.cancel")
          foreground: ctx.foreground; accent: ctx.accent; urgent: ctx.urgent; fontFamily: ctx.fontFamily
          onActivated: ctx.back()
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
