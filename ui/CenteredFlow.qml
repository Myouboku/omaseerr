import QtQuick
import qs.Commons
import "../model/hints.js" as Hints

// Lays its visible children out in centred lines, as few as fit and as
// even as possible (the same layout as KeyHints). Flow can only align
// left.
Item {
  id: flow
  property real spacing: Style.space(6)
  property real rowSpacing: Style.space(6)
  implicitHeight: 0

  function relayout() {
    var list = []
    for (var i = 0; i < children.length; i++) if (children[i].visible) list.push(children[i])
    var layout = Hints.layoutHints(list.map(function(it) { return { width: it.implicitWidth, height: it.implicitHeight } }), width, spacing, rowSpacing)
    for (var j = 0; j < layout.positions.length; j++) {
      list[j].x = layout.positions[j].x
      list[j].y = layout.positions[j].y
    }
    implicitHeight = layout.height
  }
  function schedule() { Qt.callLater(relayout) }

  // Children come and go (shown or hidden) and change size with their text.
  property var _watched: []
  onChildrenChanged: {
    for (var i = 0; i < children.length; i++) {
      var c = children[i]
      if (_watched.indexOf(c) !== -1) continue
      _watched.push(c)
      c.visibleChanged.connect(schedule)
      c.implicitWidthChanged.connect(schedule)
      c.implicitHeightChanged.connect(schedule)
    }
    schedule()
  }
  onWidthChanged: schedule()
  onVisibleChanged: schedule()
}
