import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// A labelled button, focusable with Tab and pressed with Enter or Space;
// it reports the modifiers held, so Shift can mean "approve with defaults".
Rectangle {
  id: ab
  property string label: ""
  property string glyph: ""
  property string tooltip: ""
  property bool primary: false
  property bool danger: false
  property bool busy: false
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property color urgent: Commons.Color.urgent
  property string fontFamily: Style.font.family
  signal activated(int modifiers)
  readonly property color tone: danger ? urgent : (primary ? accent : foreground)
  implicitWidth: abRow.implicitWidth + Style.space(20)
  implicitHeight: Style.spacing.controlHeight
  radius: Style.cornerRadius
  opacity: enabled ? (busy ? 0.5 : 1) : 0.4
  color: (abMouse.containsMouse || activeFocus) && enabled && !busy ? Util.alpha(tone, 0.18) : (primary ? Util.alpha(tone, 0.1) : "transparent")
  border.width: activeFocus ? 2 : 1
  border.color: activeFocus ? tone : Util.alpha(tone, primary || danger ? 0.7 : 0.35)
  activeFocusOnTab: true
  Keys.onPressed: function(event) {
    if (event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter && event.key !== Qt.Key_Space) return
    if (ab.enabled && !ab.busy) ab.activated(event.modifiers)
    event.accepted = true
  }
  Row {
    id: abRow
    anchors.centerIn: parent
    spacing: Style.space(6)
    PlainText { visible: ab.glyph !== ""; text: ab.glyph; color: ab.tone; font.family: ab.fontFamily; font.pixelSize: Style.font.icon; anchors.verticalCenter: parent.verticalCenter }
    PlainText { text: ab.busy ? "…" : ab.label; color: ab.tone; font.family: ab.fontFamily; anchors.verticalCenter: parent.verticalCenter }
  }
  MouseArea {
    id: abMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: ab.enabled && !ab.busy ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: function(mouse) { if (ab.enabled && !ab.busy) ab.activated(mouse.modifiers) }
  }
  PanelToolTip { visible: abMouse.containsMouse && ab.tooltip !== ""; text: ab.tooltip; fontFamily: ab.fontFamily }
}
