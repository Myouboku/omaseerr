import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Glyphs.js" as Glyphs

// One request in the list: poster, title, year and 4K tag, a line of
// details, then its status, or approve and decline buttons while it waits.
CursorSurface {
  id: row
  property string title: ""
  property string year: ""
  property bool is4k: false
  property string details: ""
  property bool showPoster: true
  property string posterUrl: ""
  property string posterType: "movie"
  property string status: "unknown"
  property string statusLabel: ""
  property color statusTone: foreground
  // Approve and decline buttons in place of the status.
  property bool actionable: false
  property bool busy: false
  property string approveTooltip: ""
  property string declineTooltip: ""
  // The row is the list's cursor, and the list has the keyboard.
  property bool selected: false
  property bool keyboardActive: false
  property color dim: Qt.darker(Commons.Color.foreground, 1.55)
  property color urgent: Commons.Color.urgent
  property string fontFamily: Style.font.family
  signal pointed()
  signal opened()
  signal approveClicked(int modifiers)
  signal declineClicked()

  // Only while the list itself has the keyboard (or under the mouse), so
  // a focused filter or search field is not shown alongside a lit row.
  hasCursor: selected && (keyboardActive || rowMouse.containsMouse)
  implicitHeight: Math.max(showPoster ? Style.space(54) : 0, rowContent.implicitHeight) + Style.space(10)

  MouseArea {
    id: rowMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: row.pointed()
    onClicked: row.opened()
  }

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: Style.space(6)
    anchors.rightMargin: Style.space(6)
    spacing: Style.space(10)

    Poster {
      visible: row.showPoster
      Layout.preferredWidth: Style.space(36)
      Layout.preferredHeight: Style.space(54)
      Layout.alignment: Qt.AlignVCenter
      url: row.posterUrl
      type: row.posterType
      foreground: row.foreground
      dim: row.dim
      fontFamily: row.fontFamily
    }

    ColumnLayout {
      id: rowContent
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
      spacing: Style.space(3)
      // The title gets all the room the year and the 4K tag leave, and is
      // only cut when it really does not fit; the year always shows.
      Item {
        id: titleLine
        Layout.fillWidth: true
        implicitHeight: rowTitle.implicitHeight
        readonly property real tail: (rowYear.visible ? rowYear.implicitWidth + Style.space(6) : 0)
                                   + (row4k.visible ? row4k.implicitWidth + Style.space(6) : 0)
        PlainText {
          id: rowTitle
          width: Math.min(implicitWidth, titleLine.width - titleLine.tail)
          text: row.title
          color: row.foreground
          font.family: row.fontFamily
          elide: Text.ElideRight
        }
        PlainText {
          id: rowYear
          x: rowTitle.width + Style.space(6)
          visible: text !== ""
          text: row.year
          color: row.dim
          font.family: row.fontFamily
        }
        Tag {
          id: row4k
          x: rowTitle.width + Style.space(6) + (rowYear.visible ? rowYear.implicitWidth + Style.space(6) : 0)
          anchors.verticalCenter: rowTitle.verticalCenter
          visible: row.is4k
          text: "4K"
          tone: row.dim
          fontFamily: row.fontFamily
        }
      }
      PlainText {
        Layout.fillWidth: true
        color: row.dim
        font.family: row.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        text: row.details
      }
    }

    StatusBadge {
      visible: !row.actionable
      Layout.alignment: Qt.AlignVCenter
      status: row.status
      label: row.statusLabel
      tone: row.statusTone
      fontFamily: row.fontFamily
    }
    IconButton {
      visible: row.actionable
      Layout.alignment: Qt.AlignVCenter
      glyph: Glyphs.check
      // Out of the Tab order: a and d do the same on the selected row, and
      // two stops per row would make Tab useless on a long list.
      focusable: false
      color: row.accent
      foreground: row.foreground
      accent: row.accent
      fontFamily: row.fontFamily
      busy: row.busy
      tooltip: row.approveTooltip
      onActivated: function(mods) { row.approveClicked(mods) }
    }
    IconButton {
      visible: row.actionable
      Layout.alignment: Qt.AlignVCenter
      glyph: Glyphs.close
      focusable: false
      color: row.urgent
      foreground: row.foreground
      accent: row.accent
      fontFamily: row.fontFamily
      busy: row.busy
      tooltip: row.declineTooltip
      onActivated: row.declineClicked()
    }
  }
}
