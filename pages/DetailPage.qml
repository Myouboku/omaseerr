import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../model/api.js" as Api
import "../model/details.js" as Details
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
  readonly property bool isTv: !!req && req.type === "tv"
  readonly property bool is4k: !!req && req.is4k
  readonly property var downloads: Details.downloadRows(media, is4k, 4)
  readonly property var release: Details.releaseState(media, isTv, ctx.nav.now)
  readonly property var nextEpisode: isTv ? Details.nextEpisode(media, ctx.nav.now) : null
  // The age rating of the locale's country, else the US one.
  readonly property string rating: {
    var country = String(Qt.locale(Commons.I18n.formatLocale).name).split("_")[1] || ""
    return Details.certification(media, country ? [country, "US"] : ["US"])
  }
  readonly property string originalLanguage: {
    var code = media ? media.originalLanguage : ""
    if (!code) return ""
    // In the panel's language for the common ones; else the language's own
    // name (Qt has no names in other languages), else the code.
    var key = "language." + code
    var named = ctx.t(key)
    if (named && named !== key) return named
    var own = Qt.locale(code).name !== "C" ? Qt.locale(code).nativeLanguageName : ""
    return own ? own.charAt(0).toUpperCase() + own.slice(1) : code
  }

  // The choices behind an approved request, by name: they take the
  // Radarr/Sonarr server's details (cached by the service).
  property var choices: ({ server: "", profile: "", language: "", tags: [] })
  function loadChoices() {
    choices = { server: "", profile: "", language: "", tags: [] }
    var r = req
    if (!r || r.serverId < 0 || r.status === Requests.REQUEST_PENDING || !ctx.svc || !ctx.svc.canManage) return
    var type = ctx.svc.serviceType(r)
    ctx.svc.loadServers(type, function(list, error) {
      if (error || detailRoot.req !== r) return
      detailRoot.choices = Details.choices(r, list, null)
      ctx.svc.loadServerDetails(type, r.serverId, function(details, error2) {
        if (error2 || detailRoot.req !== r) return
        detailRoot.choices = Details.choices(r, list, details)
      })
    })
  }
  onReqChanged: Qt.callLater(loadChoices)
  implicitHeight: header0.implicitHeight + Style.space(10) + detailColumn.implicitHeight
                  + (detailKeys.visible ? detailKeys.topMargin + detailKeys.implicitHeight : 0)

  // A season of the request: its name, its episodes, and where it stands
  // (available, being downloaded…) when Seerr knows.
  component SeasonLine: RowLayout {
    id: line
    property var season: null
    // The single season of a request reads like the lines around it;
    // listed seasons are dimmed under the seasons line.
    property bool strong: false
    readonly property string statusKey: season ? Details.seasonStatusKey(detailRoot.media, detailRoot.is4k, season.seasonNumber) : ""
    width: parent ? parent.width : 0
    spacing: Style.space(8)
    PlainText {
      text: line.season ? detailRoot.seasonName(line.season) : ""
      color: ctx.dim
      font.family: ctx.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    PlainText {
      Layout.fillWidth: true
      horizontalAlignment: Text.AlignRight
      text: line.season && line.season.episodeCount > 0 ? ctx.tn("approve.episodes", line.season.episodeCount) : (line.strong ? "" : "–")
      color: line.strong ? ctx.foreground : ctx.dim
      font.family: ctx.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }
    StatusBadge {
      visible: line.statusKey !== ""
      Layout.alignment: Qt.AlignVCenter
      status: line.statusKey
      label: ctx.t("statusShort." + line.statusKey)
      tone: ctx.statusColor(line.statusKey)
      fontFamily: ctx.fontFamily
    }
  }

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

      // Downloads under way, from Radarr/Sonarr through Seerr.
      Column {
        width: parent.width
        spacing: Style.space(6)
        visible: detailRoot.downloads.rows.length > 0
        FieldLabel { text: ctx.t("detail.downloads"); color: ctx.dim; font.family: ctx.fontFamily }
        Repeater {
          model: detailRoot.downloads.rows
          DownloadRow {
            required property var modelData
            width: parent.width
            title: Details.downloadLabel(modelData)
            progress: modelData.progress
            known: modelData.known
            detail: {
              var pct = modelData.known ? ctx.t("detail.percent").arg(Math.round(modelData.progress * 100)) : ""
              var left = ctx.nav.remaining(modelData.eta)
              return pct && left ? ctx.t("detail.downloadLeft").arg(pct).arg(left) : (pct || left)
            }
            tone: ctx.statusColor("processing")
            foreground: ctx.foreground; dim: ctx.dim; fontFamily: ctx.fontFamily
          }
        }
        Hint {
          visible: detailRoot.downloads.more > 0
          text: ctx.tn("detail.downloadsMore", detailRoot.downloads.more)
          color: ctx.dim; font.family: ctx.fontFamily
          font.pixelSize: Style.font.caption
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
        // When it comes out (a movie), or where a series stands.
        InfoPair {
          visible: value !== ""
          label: detailRoot.isTv ? ctx.t("detail.airing") : ctx.t("detail.release")
          value: {
            var r = detailRoot.release
            var date = ctx.nav.shortDate(r.date)
            if (detailRoot.isTv) {
              var state = { upcoming: "detail.airingUpcoming", returning: "detail.airingReturning", ended: "detail.airingEnded", canceled: "detail.airingCanceled" }[r.kind]
              if (!state) return ""
              var text = ctx.t(state)
              var n = detailRoot.nextEpisode
              if (n) text += " · " + ctx.t("detail.nextEpisode").arg(n.season).arg(n.episode).arg(ctx.nav.shortDate(n.airDate))
              else if (r.kind === "upcoming" && date) text += " · " + date
              return text
            }
            if (r.kind === "upcoming") return date ? ctx.t("detail.upcoming").arg(date) : ctx.t("detail.notOutYet")
            if (r.kind === "canceled") return ctx.t("detail.canceled")
            if (r.kind === "released" && date) return new Date(r.date).toLocaleDateString(Qt.locale(Commons.I18n.formatLocale), "d MMM yyyy")
            return ""
          }
          foreground: detailRoot.release.kind === "upcoming" && !detailRoot.isTv ? ctx.statusColor("processing") : ctx.foreground
          dim: ctx.dim; fontFamily: ctx.fontFamily
        }
        SeasonLine {
          visible: detailRoot.oneSeason
          season: detailRoot.oneSeason ? detailRoot.seasons.seasons[0] : null
          strong: true
        }
        InfoPair {
          visible: !!detailRoot.req && detailRoot.req.type === "tv" && !detailRoot.oneSeason
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
            SeasonLine {
              required property var modelData
              width: parent.width - Style.space(12)
              season: modelData
            }
          }
        }
        InfoPair {
          visible: !!detailRoot.req && detailRoot.req.rootFolder !== ""
          label: ctx.t("detail.rootFolder")
          value: detailRoot.req ? detailRoot.req.rootFolder : ""
          foreground: ctx.foreground; dim: ctx.dim; fontFamily: ctx.fontFamily
        }
        // What it was approved with.
        InfoPair {
          visible: value !== ""
          label: ctx.t("detail.server")
          value: detailRoot.choices.server
          foreground: ctx.foreground; dim: ctx.dim; fontFamily: ctx.fontFamily
        }
        InfoPair {
          visible: value !== ""
          label: ctx.t("detail.quality")
          value: detailRoot.choices.profile
          foreground: ctx.foreground; dim: ctx.dim; fontFamily: ctx.fontFamily
        }
        InfoPair {
          visible: value !== ""
          label: ctx.t("detail.language")
          value: detailRoot.choices.language
          foreground: ctx.foreground; dim: ctx.dim; fontFamily: ctx.fontFamily
        }
        InfoPair {
          visible: value !== ""
          label: ctx.t("detail.tags")
          value: detailRoot.choices.tags.join(", ")
          foreground: ctx.foreground; dim: ctx.dim; fontFamily: ctx.fontFamily
        }
      }

      // About the movie or series itself.
      Column {
        width: parent.width
        spacing: Style.spacing.labelGap
        visible: !!detailRoot.media && (detailRoot.media.people.length > 0 || detailRoot.media.networks.length > 0 || detailRoot.rating !== "" || detailRoot.originalLanguage !== "")
        InfoPair {
          visible: value !== ""
          label: detailRoot.isTv ? ctx.t("detail.createdBy") : ctx.t("detail.directedBy")
          value: detailRoot.media ? detailRoot.media.people.join(", ") : ""
          foreground: ctx.foreground; dim: ctx.dim; fontFamily: ctx.fontFamily
        }
        InfoPair {
          visible: value !== ""
          label: ctx.t("detail.network")
          value: detailRoot.media ? detailRoot.media.networks.join(", ") : ""
          foreground: ctx.foreground; dim: ctx.dim; fontFamily: ctx.fontFamily
        }
        InfoPair {
          visible: value !== ""
          label: ctx.t("detail.rating")
          value: detailRoot.rating
          foreground: ctx.foreground; dim: ctx.dim; fontFamily: ctx.fontFamily
        }
        InfoPair {
          visible: value !== ""
          label: ctx.t("detail.originalLanguage")
          value: detailRoot.originalLanguage
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

      CenteredFlow {
        width: parent.width
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
        // Then the links, and deleting last.
        ActionButton {
          visible: ctx.nav.watchUrl !== ""
          label: ctx.t("action.watch")
          glyph: Glyphs.play
          primary: true
          tooltip: ctx.t("action.watch") + "  (w)"
          foreground: ctx.foreground; accent: ctx.accent; urgent: ctx.urgent; fontFamily: ctx.fontFamily
          onActivated: ctx.nav.watch()
        }
        ActionButton {
          visible: ctx.nav.trailerUrl !== ""
          label: ctx.t("action.trailer")
          glyph: Glyphs.trailer
          tooltip: ctx.t("action.trailer") + "  (v)"
          foreground: ctx.foreground; accent: ctx.accent; urgent: ctx.urgent; fontFamily: ctx.fontFamily
          onActivated: ctx.nav.trailer()
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
      var base = r && r.status === Requests.REQUEST_PENDING ? ctx.t("detail.keys")
        : (r && r.status === Requests.REQUEST_FAILED ? ctx.t("detail.keysFailed") : ctx.t("detail.keysDone"))
      // The links' keys, when there is something to open.
      var extra = []
      if (ctx.nav.watchUrl) extra.push(ctx.t("detail.keysWatch"))
      if (ctx.nav.trailerUrl) extra.push(ctx.t("detail.keysTrailer"))
      return extra.length ? base + " · " + extra.join(" · ") : base
    }
    tone: ctx.dim
    fontFamily: ctx.fontFamily
  }
}
