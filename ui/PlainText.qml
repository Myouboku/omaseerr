import QtQuick
import qs.Commons
import qs.Commons as Commons

// Every string this panel shows may come from Seerr: never rich text.
Text {
  textFormat: Text.PlainText
  color: Commons.Color.foreground
  font.family: Style.font.family
  font.pixelSize: Style.font.body
}
