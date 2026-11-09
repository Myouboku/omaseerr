import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Glyphs.js" as Glyphs

// A poster image, with the media type's icon until (or unless) it loads.
Rectangle {
  id: poster
  property string url: ""
  property string type: "movie"
  property color foreground: Commons.Color.foreground
  property color dim: Qt.darker(Commons.Color.foreground, 1.55)
  property string fontFamily: Style.font.family
  color: Util.alpha(foreground, 0.06)
  radius: Style.cornerRadius
  clip: true
  PlainText {
    anchors.centerIn: parent
    visible: image.status !== Image.Ready
    text: poster.type === "tv" ? Glyphs.tv : Glyphs.movie
    color: poster.dim
    font.family: poster.fontFamily
    font.pixelSize: Math.round(poster.width * 0.4)
  }
  Image {
    id: image
    anchors.fill: parent
    source: poster.url
    asynchronous: true
    cache: true
    fillMode: Image.PreserveAspectCrop
    sourceSize.width: poster.width * 2
    sourceSize.height: poster.height * 2
    opacity: status === Image.Ready ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic } }
  }
}
