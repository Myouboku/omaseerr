import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Glyphs.js" as Glyphs

// A page's title row: a back button (or the app's icon), the title and an
// optional subtitle, and the page's own buttons on the right.
RowLayout {
  id: topBar
  property string title: ""
  property string subtitle: ""
  property bool subtitleUrgent: false
  property bool subtitleClickable: false
  property string subtitleTooltip: ""
  signal subtitleClicked()
  property bool showBack: false
  property string backTooltip: ""
  signal back()
  // Shown in place of the back button.
  property string icon: ""
  property color foreground: Commons.Color.foreground
  property color dim: Qt.darker(Commons.Color.foreground, 1.55)
  property color accent: Commons.Color.accent
  property color urgent: Commons.Color.urgent
  property string fontFamily: Style.font.family
  default property alias actions: actionRow.data
  spacing: Style.space(8)

  IconButton {
    visible: topBar.showBack
    glyph: Glyphs.back
    tooltip: topBar.backTooltip
    foreground: topBar.foreground
    accent: topBar.accent
    fontFamily: topBar.fontFamily
    Layout.alignment: Qt.AlignVCenter
    onActivated: topBar.back()
  }
  PlainText {
    visible: !topBar.showBack
    text: topBar.icon
    color: topBar.foreground
    font.family: topBar.fontFamily
    font.pixelSize: Style.font.display
    Layout.alignment: Qt.AlignVCenter
  }
  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.space(1)
    PlainText {
      Layout.fillWidth: true
      text: topBar.title
      color: topBar.foreground
      font.family: topBar.fontFamily
      font.pixelSize: Style.font.title
      font.bold: true
      elide: Text.ElideRight
    }
    PlainText {
      Layout.fillWidth: true
      visible: text !== ""
      text: topBar.subtitle
      color: topBar.subtitleUrgent ? topBar.urgent : (subMouse.containsMouse && topBar.subtitleClickable ? topBar.accent : topBar.dim)
      font.family: topBar.fontFamily
      font.pixelSize: Style.font.caption
      font.underline: subMouse.containsMouse && topBar.subtitleClickable
      elide: Text.ElideRight
      MouseArea {
        id: subMouse
        width: Math.min(parent.width, parent.implicitWidth)
        height: parent.height
        enabled: topBar.subtitleClickable
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: topBar.subtitleClicked()
      }
      PanelToolTip { visible: subMouse.containsMouse && topBar.subtitleClickable && topBar.subtitleTooltip !== ""; text: topBar.subtitleTooltip; fontFamily: topBar.fontFamily }
    }
  }
  Row {
    id: actionRow
    spacing: Style.space(2)
    Layout.alignment: Qt.AlignVCenter
  }
}
