import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import "Glyphs.js" as Glyphs

// Results and errors, sliding up from the bottom of the panel. Shown while
// `message` is not empty; each new `serial` brings in the current message.
Rectangle {
  id: toast
  property string message: ""
  property bool isError: false
  property int serial: 0
  property color foreground: Commons.Color.foreground
  property color success: Commons.Color.accent
  property color urgent: Commons.Color.urgent
  property string fontFamily: Style.font.family
  readonly property bool shown: message !== ""
  readonly property color tone: isError ? urgent : success
  // Keeps the last text while it fades out.
  property string text: ""
  property bool error: false
  onSerialChanged: { toast.text = toast.message; toast.error = toast.isError; pop.restart() }
  width: Math.min(parent.width - Style.space(24), toastRow.implicitWidth + Style.space(24))
  height: toastRow.implicitHeight + Style.space(14)
  radius: Style.cornerRadius
  color: Commons.Color.background
  border.width: 1
  border.color: Util.alpha(tone, 0.7)
  opacity: shown ? 1 : 0
  anchors.horizontalCenter: parent.horizontalCenter
  anchors.bottom: parent.bottom
  anchors.bottomMargin: shown ? Style.space(2) : -Style.space(10)
  visible: opacity > 0
  Behavior on opacity { NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }
  Behavior on anchors.bottomMargin { NumberAnimation { duration: Style.duration(260); easing.type: Easing.OutBack } }
  Rectangle {
    anchors.fill: parent
    radius: parent.radius
    color: Util.alpha(toast.tone, 0.12)
  }
  RowLayout {
    id: toastRow
    anchors.centerIn: parent
    width: Math.min(implicitWidth, toast.parent.width - Style.space(48))
    spacing: Style.space(8)
    PlainText {
      id: toastIcon
      text: toast.error ? Glyphs.alert : Glyphs.check
      color: toast.tone
      font.family: toast.fontFamily
      font.pixelSize: Style.font.icon
      Layout.alignment: Qt.AlignTop
      // A small bounce each time a new message arrives.
      SequentialAnimation on scale {
        id: pop
        running: false
        NumberAnimation { from: 0.4; to: 1.25; duration: Style.duration(160); easing.type: Easing.OutCubic }
        NumberAnimation { to: 1; duration: Style.duration(140); easing.type: Easing.InOutQuad }
      }
    }
    PlainText {
      Layout.fillWidth: true
      Layout.maximumWidth: toast.parent ? toast.parent.width - Style.space(80) : 300
      text: toast.text
      color: toast.foreground
      font.family: toast.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
    }
  }
}
