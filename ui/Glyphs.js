.pragma library

// Nerd Font (Material Design) glyphs the panel draws.

var seerr = "\u{f0fce}"
var movie = "\u{f0381}"
var tv = "\u{f0502}"
var check = "\u{f012c}"
var close = "\u{f0156}"
var refresh = "\u{f0450}"
var cog = "\u{f0493}"
var trash = "\u{f01b4}"
var open = "\u{f03cc}"
var back = "\u{f004d}"
var alert = "\u{f0028}"
var key = "\u{f0306}"
var bolt = "\u{f140b}"
var search = "\u{f0349}"
var sortDesc = "\u{f04bd}"
var sortAsc = "\u{f04bc}"
var retry = "\u{f0450}"
var lock = "\u{f033e}"
var warning = "\u{f0026}"
var play = "\u{f040a}"
var trailer = "\u{f05c3}"

// One icon per status, shown with its label (and alone where room is short).
function statusGlyph(key) {
  switch (key) {
  case "pending": return "\u{f0150}"      // clock
  case "processing": return "\u{f01da}"   // download
  case "partial": return "\u{f1395}"      // half circle
  case "available":
  case "completed": return "\u{f05e0}"    // check circle
  case "declined":
  case "deleted": return "\u{f0159}"      // close circle
  case "failed": return "\u{f0028}"       // alert circle
  default: return "\u{f02d7}"             // help circle
  }
}
