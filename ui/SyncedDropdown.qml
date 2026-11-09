import QtQuick
import qs.Ui

// The kit's Dropdown assigns `value` itself when an option is picked, which
// cuts a `value:` binding: the dropdown would then go on showing that pick
// after the state changes elsewhere (f/t keys, a server change resetting
// the profile, IPC `set`). Bind `current` instead; it is pushed to `value`
// on every change, and again after a pick, in case the pick was refused.
Dropdown {
  id: synced
  property string current: ""
  value: current
  onCurrentChanged: value = current
  Connections {
    target: synced
    function onChanged(v) { Qt.callLater(function() { synced.value = synced.current }) }
  }
}
