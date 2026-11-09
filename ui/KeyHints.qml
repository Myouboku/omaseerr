import QtQuick
import qs.Commons
import qs.Commons as Commons

// Keyboard shortcuts as "key label · key label …" (the translation's
// format): each pair is laid out as one unbreakable cap + label, so a line
// only ever wraps between shortcuts, never inside one. Lines are centred
// and balanced: as few as fit, with widths as even as possible.
Item {
  id: hints
  property string text: ""
  property color tone: Qt.darker(Commons.Color.foreground, 1.55)
  property string fontFamily: Style.font.family
  readonly property var entries: text.split(" · ").map(function(part) {
    var cut = part.indexOf(" ")
    return cut < 0 ? { keys: part, label: "" } : { keys: part.slice(0, cut), label: part.slice(cut + 1) }
  })
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
  // Greedy wrap at `limit`: arrays of items per line.
  function wrap(list, limit) {
    var lines = [], line = [], used = 0
    for (var i = 0; i < list.length; i++) {
      var w = list[i].implicitWidth
      if (line.length && used + hGap + w > limit) { lines.push(line); line = []; used = 0 }
      used += (line.length ? hGap : 0) + w
      line.push(list[i])
    }
    if (line.length) lines.push(line)
    return lines
  }
  function relayout() {
    var list = items()
    if (!list.length || width <= 0) { implicitHeight = 0; return }
    var count = wrap(list, width).length
    // Narrowest limit that keeps the same number of lines.
    var lo = 0, hi = width
    for (var i = 0; i < list.length; i++) lo = Math.max(lo, list[i].implicitWidth)
    while (hi - lo > 1) {
      var mid = (lo + hi) / 2
      if (wrap(list, mid).length <= count) hi = mid; else lo = mid
    }
    var lines = wrap(list, Math.min(hi, width)), y = 0
    for (var l = 0; l < lines.length; l++) {
      var row = lines[l], total = 0, tall = 0
      for (var j = 0; j < row.length; j++) { total += row[j].implicitWidth; tall = Math.max(tall, row[j].implicitHeight) }
      total += hGap * (row.length - 1)
      var x = Math.max(0, (width - total) / 2)
      for (var k = 0; k < row.length; k++) {
        row[k].x = Math.round(x)
        row[k].y = Math.round(y + (tall - row[k].implicitHeight) / 2)
        x += row[k].implicitWidth + hGap
      }
      y += tall + (l < lines.length - 1 ? vGap : 0)
    }
    implicitHeight = y
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
