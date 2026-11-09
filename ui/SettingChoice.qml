import QtQuick

// A dropdown for one value of a settings object: shows `values[key]` and
// asks for the picked one (as a number with `numeric`) through `save`.
SyncedDropdown {
  property string key: ""
  property bool numeric: false
  property var values: ({})
  signal save(var patch)
  width: parent ? parent.width : 0
  current: String(values[key])
  onChanged: function(v) {
    var patch = {}
    patch[key] = numeric ? parseInt(v, 10) : v
    save(patch)
  }
}
