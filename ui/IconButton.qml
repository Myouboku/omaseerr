import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// A glyph button that reports the modifiers held, so Shift+click can mean
// "approve with defaults".
Item {
  id: ib
  property string glyph: ""
  property string tooltip: ""
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property string fontFamily: Style.font.family
  property color color: foreground
  property bool busy: false
  // Turns while something it started is under way (refresh).
  property bool spinning: false
  signal activated(int modifiers)
  implicitWidth: Style.space(26)
  implicitHeight: Style.space(26)
  opacity: enabled ? (busy ? 0.45 : 1) : 0.35
  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: ibMouse.containsMouse && ib.enabled && !ib.busy ? Style.hoverFillFor(ib.foreground, ib.accent) : "transparent"
  }
  PlainText {
    id: ibGlyph
    anchors.centerIn: parent
    text: ib.glyph
    color: ib.color
    font.family: ib.fontFamily
    font.pixelSize: Style.font.icon
    RotationAnimator on rotation {
      running: ib.spinning
      from: 0; to: 360
      duration: 900
      loops: Animation.Infinite
      onRunningChanged: if (!running) ibGlyph.rotation = 0
    }
  }
  MouseArea {
    id: ibMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: ib.enabled && !ib.busy ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: function(mouse) { if (ib.enabled && !ib.busy) ib.activated(mouse.modifiers) }
  }
  PanelToolTip { visible: ibMouse.containsMouse && ib.tooltip !== ""; text: ib.tooltip; fontFamily: ib.fontFamily }
}
