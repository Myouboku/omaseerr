import QtQuick
import qs.Commons
import qs.Commons as Commons
import "../model/hints.js" as Hints

// Keyboard shortcuts as "key label · key label …" (the translation's
// format): each pair is laid out as one unbreakable cap + label, so a line
// only ever wraps between shortcuts, never inside one. Lines are centred
// and balanced: as few as fit, with widths as even as possible. This
// measures the pairs; model/hints.js reads the text and places them.
Item {
  id: hints
  property string text: ""
  property color tone: Qt.darker(Commons.Color.foreground, 1.55)
  property string fontFamily: Style.font.family
  readonly property var entries: Hints.parseHints(text)
  readonly property real hGap: Style.space(8)
  readonly property real vGap: Style.space(4)
  implicitHeight: 0

  function items() {
    var out = []
    for (var i = 0; i < pairs.count; i++) {
      var it = pairs.itemAt(i)
      if (it) out.push(it)
    }
    return out
  }
  function relayout() {
    var list = items()
    var layout = Hints.layoutHints(list.map(function(it) { return { width: it.implicitWidth, height: it.implicitHeight } }), width, hGap, vGap)
    for (var i = 0; i < layout.positions.length; i++) {
      list[i].x = layout.positions[i].x
      list[i].y = layout.positions[i].y
    }
    implicitHeight = layout.height
  }
  onWidthChanged: Qt.callLater(relayout)

  Repeater {
    id: pairs
    model: hints.entries
    onItemAdded: Qt.callLater(hints.relayout)
    onItemRemoved: Qt.callLater(hints.relayout)
    Row {
      required property var modelData
      spacing: Style.space(3)
      onImplicitWidthChanged: Qt.callLater(hints.relayout)
      Tag {
        anchors.verticalCenter: parent.verticalCenter
        text: modelData.keys
        tone: hints.tone
        fontFamily: hints.fontFamily
      }
      PlainText {
        anchors.verticalCenter: parent.verticalCenter
        text: modelData.label
        color: hints.tone
        font.family: hints.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
