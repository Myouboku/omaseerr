import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Glyphs.js" as Glyphs

// A pill that can be ticked, such as a tag or a season.
Rectangle {
  id: chip
  property string label: ""
  property string tooltip: ""
  property bool selected: false
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property string fontFamily: Style.font.family
  signal activated()
  implicitWidth: chipLabel.implicitWidth + Style.space(16)
  implicitHeight: chipLabel.implicitHeight + Style.space(8)
  radius: height / 2
  color: selected ? Util.alpha(accent, 0.2) : (chipMouse.containsMouse || activeFocus ? Style.hoverFillFor(foreground, accent) : "transparent")
  border.width: activeFocus ? 2 : 1
  border.color: selected || activeFocus ? accent : Util.alpha(foreground, 0.3)
  // Space ticks it; Enter is left to the form (approve).
  activeFocusOnTab: true
  Keys.onSpacePressed: chip.activated()
  PlainText {
    id: chipLabel
    anchors.centerIn: parent
    text: (chip.selected ? Glyphs.check + " " : "") + chip.label
    color: chip.selected ? chip.accent : chip.foreground
    font.family: chip.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
  MouseArea {
    id: chipMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: chip.activated()
  }
  PanelToolTip { visible: chipMouse.containsMouse && chip.tooltip !== ""; text: chip.tooltip; fontFamily: chip.fontFamily }
}
