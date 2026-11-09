import QtQuick
import qs.Commons

// A small outlined label, such as "4K".
Rectangle {
  id: tag
  property alias text: label.text
  property color tone: Qt.darker(Commons.Color.foreground, 1.55)
  property string fontFamily: Style.font.family

  implicitWidth: label.implicitWidth + Style.space(8)
  implicitHeight: label.implicitHeight + Style.space(2)
  radius: Style.space(3)
  color: "transparent"
  border.width: 1
  border.color: tone

  Text {
    id: label
    anchors.centerIn: parent
    textFormat: Text.PlainText
    color: tag.tone
    font.family: tag.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
  }
}
