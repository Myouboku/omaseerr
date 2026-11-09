import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons

// One download under way: its name, how far it is and when it should end,
// and a bar showing it.
ColumnLayout {
  id: dl
  property string title: ""
  // 0 to 1; `known` is false when the size is not known yet.
  property real progress: 0
  property bool known: true
  // What goes on the right: "45 % · 25 min left".
  property string detail: ""
  property color foreground: Commons.Color.foreground
  property color dim: Qt.darker(Commons.Color.foreground, 1.55)
  property color tone: Commons.Color.accent
  property string fontFamily: Style.font.family
  width: parent ? parent.width : 0
  spacing: Style.space(3)

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.space(8)
    PlainText {
      Layout.fillWidth: true
      text: dl.title
      color: dl.foreground
      font.family: dl.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideMiddle
    }
    PlainText {
      text: dl.detail
      color: dl.dim
      font.family: dl.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
  Rectangle {
    Layout.fillWidth: true
    implicitHeight: Style.space(4)
    radius: height / 2
    color: Util.alpha(dl.foreground, 0.12)
    Rectangle {
      width: dl.known ? parent.width * dl.progress : 0
      height: parent.height
      radius: parent.radius
      color: dl.tone
      Behavior on width { NumberAnimation { duration: Style.duration(400); easing.type: Easing.OutCubic } }
    }
  }
}
