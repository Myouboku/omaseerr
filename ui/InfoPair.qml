import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons

// A label on the left, its value on the right.
RowLayout {
  id: pair
  property string label: ""
  property string value: ""
  property color foreground: Commons.Color.foreground
  property color dim: Qt.darker(Commons.Color.foreground, 1.55)
  property string fontFamily: Style.font.family
  width: parent ? parent.width : 0
  spacing: Style.space(8)
  PlainText { text: pair.label; color: pair.dim; font.family: pair.fontFamily; font.pixelSize: Style.font.bodySmall }
  PlainText {
    Layout.fillWidth: true
    horizontalAlignment: Text.AlignRight
    text: pair.value
    color: pair.foreground
    font.family: pair.fontFamily
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideRight
  }
}
