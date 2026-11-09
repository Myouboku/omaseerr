import QtQuick
import qs.Commons

// A page fades in when it is shown.
NumberAnimation {
  from: 0.35; to: 1
  duration: Style.duration(140)
  easing.type: Easing.OutCubic
  running: target ? target.visible : false
}
