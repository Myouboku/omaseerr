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

// The requests: filters, search, the rows, and what to say when there are none.
Item {
  id: listRoot
  // The panel: state, actions, service, settings, translations and theme.
  required property var ctx
  property alias flick: flick
  property alias rowRepeater: rowRepeater
  property alias searchField: search
  implicitHeight: header.implicitHeight + Style.space(10) + Math.max(Style.space(60), flick.contentHeight)
                  + (listKeys.visible ? listKeys.topMargin + listKeys.implicitHeight : 0)

  // The line under a request's title: type, seasons, who asked, and when.
  function rowDetails(r) {
    if (!r) return ""
    var parts = [(r.type === "tv" ? Glyphs.tv + " " + ctx.t("type.tv") : Glyphs.movie + " " + ctx.t("type.movie"))]
    if (r.type === "tv" && r.seasons.length) parts.push(ctx.t("detail.seasonsShort").arg(Requests.seasonsLabel(r.seasons)))
    if (r.requestedBy) parts.push(r.requestedBy.name)
    parts.push(ctx.nav.age(ctx.svc && ctx.svc.view.sort === "modified" ? r.updatedAt : r.createdAt))
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
        if (!ctx.svc) return ""
        if (ctx.offline) return ctx.retrying ? ctx.t("bar.connecting") : ctx.t("bar.error")
        if (ctx.svc.connection === "connected") return ctx.tn("list.pendingCount", ctx.pending)
        if (ctx.svc.connection === "connecting") return ctx.t("bar.connecting")
        if (ctx.svc.connection === "unconfigured") return ctx.t("bar.setup")
        return ctx.t("bar.error")
      }
      subtitleUrgent: ctx.offline && !ctx.retrying
      // The pending count takes you to the pending requests.
      subtitleClickable: ctx.connected && ctx.pending > 0 && !!ctx.svc && ctx.svc.view.filter !== "pending"
      subtitleTooltip: ctx.t("filter.pending") + "  (f)"
      onSubtitleClicked: { ctx.nav.cursor = 0; ctx.svc.setView({ filter: "pending" }) }
      showBack: false
      foreground: ctx.foreground; dim: ctx.dim; accent: ctx.accent; urgent: ctx.urgent; fontFamily: ctx.fontFamily
      IconButton {
        glyph: Glyphs.refresh
        tooltip: ctx.t("action.refresh") + "  (r)"
        spinning: !!ctx.svc && (ctx.svc.listLoading || ctx.svc.connection === "connecting")
        foreground: ctx.foreground; accent: ctx.accent; fontFamily: ctx.fontFamily
        onActivated: if (ctx.svc) ctx.svc.refresh()
      }
      IconButton {
        glyph: Glyphs.open; tooltip: ctx.t("action.openSeerr") + "  (o)"; enabled: !!ctx.svc && ctx.svc.baseUrl !== ""
        foreground: ctx.foreground; accent: ctx.accent; fontFamily: ctx.fontFamily
        onActivated: ctx.svc.openInBrowser(null)
      }
      IconButton {
        glyph: Glyphs.cog; tooltip: ctx.t("settings.title") + "  (s)"
        foreground: ctx.foreground; accent: ctx.accent; fontFamily: ctx.fontFamily
        onActivated: ctx.nav.go("settings")
      }
    }

    // Filters: status, type, sort, direction.
    RowLayout {
      width: parent.width
      spacing: Style.space(6)
      visible: ctx.connected
      SyncedDropdown {
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        showLabel: false
        current: ctx.svc ? ctx.svc.view.filter : "pending"
        options: Requests.FILTERS.map(function(f) { return { value: f, label: ctx.t("filter." + f) } })
        foreground: ctx.foreground
        fontFamily: ctx.fontFamily
        onChanged: function(v) { ctx.nav.cursor = 0; ctx.svc.setView({ filter: v }) }
      }
      SyncedDropdown {
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        showLabel: false
        current: ctx.svc ? ctx.svc.view.mediaType : "all"
        options: Requests.MEDIA_TYPES.map(function(f) { return { value: f, label: ctx.t("mediaType." + f) } })
        foreground: ctx.foreground
        fontFamily: ctx.fontFamily
        onChanged: function(v) { ctx.nav.cursor = 0; ctx.svc.setView({ mediaType: v }) }
      }
      SyncedDropdown {
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        showLabel: false
        // Sort and order in one choice, each spelled out ("Newest").
        current: Requests.sortChoice(ctx.svc ? ctx.svc.view : null)
        options: Requests.sortChoices().map(function(c) { return { value: c.value, label: ctx.t("sortBy." + c.sort + "." + c.direction) } })
        foreground: ctx.foreground
        fontFamily: ctx.fontFamily
        onChanged: function(v) {
          ctx.nav.cursor = 0
          ctx.svc.setView(Requests.sortPatch(v))
        }
      }
    }

    TextField {
      id: search
      width: parent.width
      visible: ctx.connected
      placeholderText: ctx.t("list.search") + "  (/)"
      foreground: ctx.foreground
      font.family: ctx.fontFamily
      font.pixelSize: Style.font.body
      onTextChanged: if (ctx.svc && text !== ctx.svc.view.search) { ctx.nav.cursor = 0; ctx.svc.setView({ search: text }) }
      // Enter hands the keyboard back to the list, keeping the search. Taken
      // here: the field lets Return through after `accepted`, and the list
      // would then open the selected request as well.
      Keys.onReturnPressed: function(event) { if (ctx.content) ctx.content.forceActiveFocus(); event.accepted = true }
      Keys.onEnterPressed: function(event) { if (ctx.content) ctx.content.forceActiveFocus(); event.accepted = true }
      Connections {
        target: ctx.svc
        ignoreUnknownSignals: true
        function onViewChanged() { if (ctx.svc.view.search !== search.text) search.text = ctx.svc.view.search }
      }
    }

    // Seerr stopped answering: what follows is from before.
    OfflineBanner {
      width: parent.width
      visible: ctx.offline && ctx.nav.visibleRows.length > 0
      title: ctx.svc && ctx.svc.lastOkAt > 0
        ? ctx.t("list.offlineSince").arg(new Date(ctx.svc.lastOkAt).toLocaleTimeString(Qt.locale(Commons.I18n.formatLocale), Locale.ShortFormat))
        : ctx.t("list.offlineTitle")
      detail: ctx.svc ? ctx.svc.lastError : ""
      retryLabel: ctx.t("action.retry")
      retrying: ctx.retrying
      foreground: ctx.foreground; dim: ctx.dim; accent: ctx.accent; urgent: ctx.urgent; fontFamily: ctx.fontFamily
      onRetry: ctx.svc.refresh()
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
    onContentYChanged: if (ctx.svc && contentY + height > contentHeight - Style.space(80)) ctx.svc.loadMore()

    Column {
      id: rowCol
      width: flick.width
      spacing: Style.space(4)
      opacity: ctx.offline ? 0.45 : 1
      Behavior on opacity { NumberAnimation { duration: Style.duration(200) } }
      Repeater {
        id: rowRepeater
        model: ctx.nav.visibleRows
        RequestRow {
          id: row
          required property var modelData
          required property int index
          readonly property var req: modelData
          readonly property var media: ctx.svc ? (ctx.svc.mediaRevision, ctx.svc.mediaFor(req)) : null
          width: rowCol.width
          title: ctx.svc ? ctx.svc.nameFor(req) : ""
          year: ctx.svc ? (ctx.svc.mediaRevision, ctx.svc.yearFor(req)) : ""
          is4k: !!req.is4k
          details: listRoot.rowDetails(req)
          showPoster: ctx.cfg.showPosters
          posterUrl: ctx.cfg.showPosters ? Api.posterUrl(media ? media.posterPath : "", "w92") : ""
          posterType: req.type
          status: Requests.statusKey(req)
          statusLabel: ctx.t("statusShort." + row.status)
          statusTone: ctx.statusColor(row.status)
          actionable: req.status === Requests.REQUEST_PENDING && !!ctx.svc && ctx.svc.canManage && !ctx.offline
          busy: !!ctx.svc && ctx.svc.isBusy(req.id)
          approveTooltip: ctx.t("action.approve") + "  (a)\n" + ctx.t("hint.shiftApprove")
          declineTooltip: ctx.t("action.decline") + "  (d)"
          selected: ctx.nav.cursor === row.index
          keyboardActive: ctx.nav.listFocused
          foreground: ctx.foreground; dim: ctx.dim; accent: ctx.accent; urgent: ctx.urgent; fontFamily: ctx.fontFamily
          onPointed: ctx.nav.cursor = row.index
          onOpened: ctx.nav.openDetail(req)
          onApproveClicked: function(mods) { ctx.nav.approve(req, (mods & Qt.ShiftModifier) !== 0) }
          onDeclineClicked: ctx.nav.decline(req)
        }
      }
    }

    // Below the rows, or centred in the empty list when there are none.
    Column {
      id: footer
      readonly property real gap: Style.space(6)
      y: ctx.nav.visibleRows.length > 0 ? rowCol.implicitHeight + gap
                                     : Math.max(0, Math.round((flick.height - implicitHeight) / 2))
      width: flick.width
      spacing: Style.space(6)

      // Unreachable with nothing to show: say so here, with a way out.
      PlainText {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: ctx.offline && ctx.nav.visibleRows.length === 0
        text: Glyphs.warning
        color: ctx.retrying ? ctx.dim : ctx.urgent
        font.family: ctx.fontFamily
        font.pixelSize: Style.font.display
      }
      PlainText {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        visible: ctx.offline && ctx.nav.visibleRows.length === 0
        text: ctx.t("list.offlineTitle")
        color: ctx.foreground
        font.family: ctx.fontFamily
        font.bold: true
      }
      Hint {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        visible: text !== ""
        text: {
          if (!ctx.svc) return ""
          if (ctx.offline) return ctx.nav.visibleRows.length === 0 ? ctx.svc.lastError : ""
          if (ctx.svc.connection === "unconfigured") return ctx.t("list.setupHint")
          if (ctx.svc.connection !== "connected") return ""
          if (ctx.svc.listError) return ctx.svc.listError
          if (ctx.svc.listLoading) return ctx.t("list.loading")
          if (ctx.nav.visibleRows.length > 0) return ""
          var v = ctx.svc.view
          var empty = Requests.emptyListMessage(v)
          return empty.arg !== "" ? ctx.t(empty.key).arg(empty.arg) : ctx.t(empty.key)
        }
        color: ctx.svc && ctx.svc.listError ? ctx.urgent : ctx.dim
        font.family: ctx.fontFamily
      }
      Hint {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        visible: ctx.connected && !!ctx.svc && ctx.svc.view.search !== "" && ctx.nav.visibleRows.length === 0 && !ctx.svc.listLoading
        text: ctx.t("list.clearSearch")
        color: ctx.dim
        font.family: ctx.fontFamily
        font.pixelSize: Style.font.caption
      }
      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(6)
        visible: (ctx.offline && ctx.nav.visibleRows.length === 0) || (!!ctx.svc && ctx.svc.connection === "unconfigured")
        ActionButton {
          visible: ctx.offline
          label: ctx.t("action.retry")
          glyph: Glyphs.retry
          primary: true
          busy: ctx.retrying
          foreground: ctx.foreground; accent: ctx.accent; urgent: ctx.urgent; fontFamily: ctx.fontFamily
          onActivated: ctx.svc.refresh()
        }
        ActionButton {
          label: ctx.t("settings.title")
          glyph: Glyphs.cog
          foreground: ctx.foreground; accent: ctx.accent; urgent: ctx.urgent; fontFamily: ctx.fontFamily
          onActivated: ctx.nav.go("settings")
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
    visible: ctx.connected
    text: ctx.t("list.keys")
    tone: ctx.dim
    fontFamily: ctx.fontFamily
  }
}
