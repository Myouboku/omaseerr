import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Glyphs.js" as Glyphs

// A status as an icon and a word. The caller picks the word: the list uses
// the short one, where the title needs the room.
Rectangle {
  id: badge
  property string status: "unknown"
  property string label: ""
  property color tone: Commons.Color.foreground
  property string fontFamily: Style.font.family
  implicitWidth: badgeRow.implicitWidth + Style.space(12)
  implicitHeight: badgeRow.implicitHeight + Style.space(4)
  radius: height / 2
  color: Util.alpha(tone, 0.14)
  border.width: 1
  border.color: Util.alpha(tone, 0.5)
  Behavior on color { ColorAnimation { duration: Style.duration(250) } }
  Row {
    id: badgeRow
    anchors.centerIn: parent
    spacing: Style.space(4)
    PlainText {
      anchors.verticalCenter: parent.verticalCenter
      text: Glyphs.statusGlyph(badge.status)
      color: badge.tone
      font.family: badge.fontFamily
      font.pixelSize: Style.font.caption
    }
    PlainText {
      anchors.verticalCenter: parent.verticalCenter
      text: badge.label
      color: badge.tone
      font.family: badge.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
