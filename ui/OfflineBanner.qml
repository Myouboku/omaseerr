import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import "Glyphs.js" as Glyphs

// Shown above stale rows while the server does not answer.
Rectangle {
  id: banner
  property string title: ""
  property string detail: ""
  property string retryLabel: ""
  // Dimmed rather than red while a retry is under way.
  property bool retrying: false
  property color foreground: Commons.Color.foreground
  property color dim: Qt.darker(Commons.Color.foreground, 1.55)
  property color accent: Commons.Color.accent
  property color urgent: Commons.Color.urgent
  property string fontFamily: Style.font.family
  signal retry()
  implicitHeight: bannerRow.implicitHeight + Style.space(12)
  radius: Style.cornerRadius
  color: Util.alpha(retrying ? dim : urgent, 0.12)
  border.width: 1
  border.color: Util.alpha(retrying ? dim : urgent, 0.5)
  RowLayout {
    id: bannerRow
    anchors.fill: parent
    anchors.leftMargin: Style.space(10)
    anchors.rightMargin: Style.space(6)
    spacing: Style.space(8)
    PlainText {
      text: Glyphs.warning
      color: banner.retrying ? banner.dim : banner.urgent
      font.family: banner.fontFamily
      Layout.alignment: Qt.AlignVCenter
    }
    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.space(1)
      PlainText {
        Layout.fillWidth: true
        text: banner.title
        color: banner.foreground
        font.family: banner.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        elide: Text.ElideRight
      }
      PlainText {
        Layout.fillWidth: true
        text: banner.detail
        color: banner.dim
        font.family: banner.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }
    ActionButton {
      Layout.alignment: Qt.AlignVCenter
      label: banner.retryLabel
      glyph: Glyphs.retry
      busy: banner.retrying
      foreground: banner.foreground
      accent: banner.accent
      urgent: banner.urgent
      fontFamily: banner.fontFamily
      onActivated: banner.retry()
    }
  }
}
