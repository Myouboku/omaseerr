import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// A glyph button that reports the modifiers held, so Shift+click can mean
// "approve with defaults". Reachable with Tab and activated with Enter or
// Space, unless `focusable` is off (a row's buttons, which its keys cover).
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
  property bool focusable: true
  signal activated(int modifiers)
  activeFocusOnTab: focusable
  Keys.onPressed: function(event) {
    if (event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter && event.key !== Qt.Key_Space) return
    if (ib.enabled && !ib.busy) ib.activated(event.modifiers)
    event.accepted = true
  }
  implicitWidth: Style.space(26)
  implicitHeight: Style.space(26)
  opacity: enabled ? (busy ? 0.45 : 1) : 0.35
  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: (ibMouse.containsMouse || ib.activeFocus) && ib.enabled && !ib.busy ? Style.hoverFillFor(ib.foreground, ib.accent) : "transparent"
    border.width: ib.activeFocus ? 2 : 0
    border.color: ib.accent
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
  PanelToolTip { visible: (ibMouse.containsMouse || ib.activeFocus) && ib.tooltip !== ""; text: ib.tooltip; fontFamily: ib.fontFamily }
}
