import QtQuick
import qs.Ui

// A toggle for one boolean of a settings object: shows `values[key]` and
// asks for the flipped value through `save`.
Toggle {
  property string key: ""
  property var values: ({})
  signal save(var patch)
  width: parent ? parent.width : 0
  checked: values[key] === true
  onClicked: {
    var patch = {}
    patch[key] = !checked
    save(patch)
  }
}
