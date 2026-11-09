import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../model/api.js" as Api
import "../model/requests.js" as Requests
import "../ui"
import "../ui/Glyphs.js" as Glyphs

// One request: poster, facts, overview and its actions.
Item {
  id: detailRoot
  // The panel: state, actions, service, settings, translations and theme.
  required property var ctx
  readonly property var req: ctx.nav.detailReq
  readonly property var media: req && ctx.svc ? (ctx.svc.mediaRevision, ctx.svc.mediaFor(req)) : null
  readonly property string status: Requests.statusKey(req)
  // The requested seasons with their episodes, from the series' details.
  readonly property var seasons: req && req.type === "tv"
    ? Requests.requestedSeasons(req.seasons, media ? media.seasons : null)
    : ({ seasons: [], total: -1 })
  readonly property bool oneSeason: seasons.seasons.length === 1
  // "Season 3", or the details' own name for the specials (season 0).
  function seasonName(season) {
    return season.seasonNumber === 0 && season.name ? season.name : ctx.t("approve.season").arg(season.seasonNumber)
  }
  readonly property bool busy: !!req && !!ctx.svc && ctx.svc.isBusy(req.id)
  implicitHeight: header0.implicitHeight + Style.space(10) + detailColumn.implicitHeight
                  + (detailKeys.visible ? detailKeys.topMargin + detailKeys.implicitHeight : 0)

  TopBar {
    id: header0
    width: parent.width
    title: detailRoot.req ? ctx.t("detail.title") : ctx.t("list.loading")
    showBack: true
    backTooltip: ctx.t("action.back") + "  (Esc)"
    foreground: ctx.foreground; dim: ctx.dim; accent: ctx.accent; urgent: ctx.urgent; fontFamily: ctx.fontFamily
    onBack: ctx.nav.back()
    IconButton {
      glyph: Glyphs.open; tooltip: ctx.t("action.openSeerr") + "  (o)"; enabled: !!detailRoot.req
      foreground: ctx.foreground; accent: ctx.accent; fontFamily: ctx.fontFamily
      onActivated: ctx.svc.openInBrowser(detailRoot.req)
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
          visible: ctx.cfg.showPosters
          width: Style.space(92)
          height: Style.space(138)
          url: ctx.cfg.showPosters ? Api.posterUrl(detailRoot.media ? detailRoot.media.posterPath : "", "w185") : ""
          type: detailRoot.req ? detailRoot.req.type : "movie"
          foreground: ctx.foreground; dim: ctx.dim; fontFamily: ctx.fontFamily
        }
        Column {
          width: parent.width - (ctx.cfg.showPosters ? Style.space(104) : 0)
          spacing: Style.space(5)
          PlainText {
            width: parent.width
            // The list's fallback ("Movie #123") when TMDB had no details.
            text: detailRoot.req && ctx.svc ? (ctx.svc.mediaRevision, ctx.svc.nameFor(detailRoot.req)) : ""
            color: ctx.foreground
            font.family: ctx.fontFamily
            font.pixelSize: Style.font.heading
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
          }
          PlainText {
            width: parent.width
            color: ctx.dim
            font.family: ctx.fontFamily
            text: {
              var r = detailRoot.req, m = detailRoot.media
              if (!r) return ""
              var parts = []
              if (m && m.year) parts.push(m.year)
              parts.push(r.type === "tv" ? ctx.t("type.tv") : ctx.t("type.movie"))
              if (r.is4k) parts.push("4K")
              if (m && m.runtime) parts.push(ctx.t("detail.runtime").arg(m.runtime))
              if (m && m.seasonCount) parts.push(ctx.tn("detail.seasonCount", m.seasonCount))
              if (m && m.vote) parts.push("★ " + Commons.I18n.formatNumber(m.vote, 1))
              return parts.join(" · ")
            }
          }
          PlainText {
            width: parent.width
            visible: text !== ""
            color: ctx.dim
            font.family: ctx.fontFamily
            font.pixelSize: Style.font.bodySmall
            text: detailRoot.media ? detailRoot.media.genres.join(", ") : ""
            elide: Text.ElideRight
          }
          StatusBadge {
            status: detailRoot.status
            label: ctx.t("status." + detailRoot.status)
            tone: ctx.statusColor(detailRoot.status)
            fontFamily: ctx.fontFamily
          }
        }
      }

      Column {
        width: parent.width
        spacing: Style.spacing.labelGap
        InfoPair {
          label: ctx.t("detail.requestedBy"); value: detailRoot.req && detailRoot.req.requestedBy ? detailRoot.req.requestedBy.name : ""
          foreground: ctx.foreground; dim: ctx.dim; fontFamily: ctx.fontFamily
        }
        InfoPair {
          label: ctx.t("detail.requested"); value: detailRoot.req ? ctx.nav.longDate(detailRoot.req.createdAt) : ""
          foreground: ctx.foreground; dim: ctx.dim; fontFamily: ctx.fontFamily
        }
        InfoPair {
          visible: !!detailRoot.req && !!detailRoot.req.modifiedBy
          label: detailRoot.status === "declined" ? ctx.t("detail.declinedBy") : ctx.t("detail.modifiedBy")
          value: detailRoot.req && detailRoot.req.modifiedBy ? detailRoot.req.modifiedBy.name : ""
          foreground: ctx.foreground; dim: ctx.dim; fontFamily: ctx.fontFamily
        }
        InfoPair {
          visible: !!detailRoot.req && detailRoot.req.updatedAt > detailRoot.req.createdAt + 1000
          label: ctx.t("detail.updated")
          value: detailRoot.req ? ctx.nav.longDate(detailRoot.req.updatedAt) : ""
          foreground: ctx.foreground; dim: ctx.dim; fontFamily: ctx.fontFamily
        }
        InfoPair {
          visible: !!detailRoot.req && detailRoot.req.type === "tv"
          // One season: just that season and its episodes, on this line.
          label: detailRoot.oneSeason ? detailRoot.seasonName(detailRoot.seasons.seasons[0]) : ctx.t("detail.seasons")
          value: {
            if (!detailRoot.req) return ""
            if (detailRoot.oneSeason) {
              var only = detailRoot.seasons.seasons[0]
              return only.episodeCount > 0 ? ctx.tn("approve.episodes", only.episodeCount) : ""
            }
            var label = Requests.seasonsLabel(detailRoot.req.seasons)
            var total = detailRoot.seasons.total
            return total > 0 ? label + " · " + ctx.tn("approve.episodes", total) : label
          }
          foreground: ctx.foreground; dim: ctx.dim; fontFamily: ctx.fontFamily
        }
        // Each requested season and its episodes, under the seasons line,
        // once the series' details are in.
        Column {
          width: parent.width
          visible: !!detailRoot.req && detailRoot.req.type === "tv" && detailRoot.seasons.seasons.length > 1 && !!detailRoot.media
          leftPadding: Style.space(12)
          spacing: Style.spacing.labelGap
          Repeater {
            model: detailRoot.seasons.seasons
            InfoPair {
              required property var modelData
              width: parent.width - Style.space(12)
              label: detailRoot.seasonName(modelData)
              value: modelData.episodeCount > 0 ? ctx.tn("approve.episodes", modelData.episodeCount) : "–"
              foreground: ctx.dim; dim: ctx.dim; fontFamily: ctx.fontFamily
            }
          }
        }
        InfoPair {
          visible: !!detailRoot.req && detailRoot.req.rootFolder !== ""
          label: ctx.t("detail.rootFolder")
          value: detailRoot.req ? detailRoot.req.rootFolder : ""
          foreground: ctx.foreground; dim: ctx.dim; fontFamily: ctx.fontFamily
        }
      }

      PanelSeparator { foreground: ctx.foreground; visible: overview.text !== "" }

      PlainText {
        id: overview
        width: parent.width
        visible: text !== ""
        text: detailRoot.media ? detailRoot.media.overview : ""
        color: ctx.foreground
        font.family: ctx.fontFamily
        wrapMode: Text.WordWrap
        font.pixelSize: Style.font.bodySmall
        lineHeight: 1.15
      }

      Flow {
        width: parent.width
        spacing: Style.space(6)
        visible: !!detailRoot.req
        ActionButton {
          visible: !!detailRoot.req && detailRoot.req.status === Requests.REQUEST_PENDING && !!ctx.svc && ctx.svc.canManage
          label: ctx.t("action.approve")
          glyph: Glyphs.check
          primary: true
          busy: detailRoot.busy
          tooltip: ctx.t("hint.shiftApprove")
          foreground: ctx.foreground; accent: ctx.accent; urgent: ctx.urgent; fontFamily: ctx.fontFamily
          onActivated: function(mods) { ctx.nav.approve(detailRoot.req, (mods & Qt.ShiftModifier) !== 0) }
        }
        ActionButton {
          visible: !!detailRoot.req && detailRoot.req.status === Requests.REQUEST_PENDING && !!ctx.svc && ctx.svc.canManage
          label: ctx.t("action.decline")
          glyph: Glyphs.close
          busy: detailRoot.busy
          foreground: ctx.foreground; accent: ctx.accent; urgent: ctx.urgent; fontFamily: ctx.fontFamily
          onActivated: ctx.nav.decline(detailRoot.req)
        }
        ActionButton {
          visible: !!detailRoot.req && detailRoot.req.status === Requests.REQUEST_FAILED && !!ctx.svc && ctx.svc.canManage
          label: ctx.t("action.retry")
          glyph: Glyphs.retry
          busy: detailRoot.busy
          foreground: ctx.foreground; accent: ctx.accent; urgent: ctx.urgent; fontFamily: ctx.fontFamily
          onActivated: ctx.svc.retry(detailRoot.req.id)
        }
        ActionButton {
          label: ctx.t("action.delete")
          glyph: Glyphs.trash
          danger: true
          busy: detailRoot.busy
          foreground: ctx.foreground; accent: ctx.accent; urgent: ctx.urgent; fontFamily: ctx.fontFamily
          onActivated: ctx.nav.remove(detailRoot.req)
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
      if (r && r.status === Requests.REQUEST_PENDING) return ctx.t("detail.keys")
      if (r && r.status === Requests.REQUEST_FAILED) return ctx.t("detail.keysFailed")
      return ctx.t("detail.keysDone")
    }
    tone: ctx.dim
    fontFamily: ctx.fontFamily
  }
}
