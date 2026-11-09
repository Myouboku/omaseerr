// The panel's keys: which action a key press stands for, given the page and
// where the keyboard focus is. panel/Keyboard.qml names the key, asks here,
// and carries the action out.
.pragma library
.import "requests.js" as Requests

// `press` describes the key and the panel:
//   key            the key's name for keys that type nothing: "Escape",
//                  "Return", "Enter", "Up", "Down", "PageUp", "PageDown",
//                  "Home", "End", "Backspace", "Delete" (else "")
//   text, shift    what the key typed, and whether Shift was held. A
//                  letter is read in lower case and its capital variant
//                  (A, F, R, S, T) taken from Shift alone, so Caps Lock
//                  never turns `a` into a quick approval.
//   page           "list" | "detail" | "approve" | "settings"
//   confirmOpen    the confirmation question is up
//   inControl      the page has a control focused (a field, a dropdown, a
//                  button…) rather than the page's own key handling
//   searchFocused  the list's search field has the focus
//   searching      the list is filtered by a search
//   status         the current request's status (0 without one)
// Returns null when the key is not the panel's (so it goes on to whatever
// has focus), else { action, … }:
//   confirm                     the confirmation question takes the key
//   leaveControl {clearSearch}  focus back to the page's keys
//   back                        the previous page, or close
//   submit {quick}              send the approval form
//   move {by}                   cursor (list) or request (detail) by rows
//   move {to: "first"|"last"}   to the list's first or last row/request
//   openDetail, approve {quick}, decline, remove, retry, open, refresh,
//   settings, focusSearch       on the current request / panel
//   watch, trailer              the details' media server page, trailer
//   cycle {key, values, backwards}  the list's next filter, type, sort…
function keyAction(press) {
  var key = press.key || ""
  var text = press.text || ""
  var shift = !!press.shift
  var letter = /^[a-zA-Z]$/.test(text) ? text.toLowerCase() : ""
  var page = press.page
  if (press.confirmOpen) return { action: "confirm" }

  if (key === "Escape") {
    // On the list and the approval form, Escape first leaves a control
    // for the page's own keys; the next one goes back.
    if (press.inControl && (page === "list" || page === "approve"))
      return { action: "leaveControl", clearSearch: page === "list" && !!press.searchFocused && !!press.searching }
    return { action: "back" }
  }
  // Typing goes to text fields; only Escape above reaches us from them.
  if (page === "settings" || page === "approve") {
    if (page === "approve" && (key === "Return" || key === "Enter")) return { action: "submit", quick: shift }
    return null
  }

  if (key === "Down" && press.searchFocused) return { action: "leaveControl", clearSearch: false }
  if (key === "Down" || (letter === "j" && !shift)) return { action: "move", by: 1 }
  if (key === "Up" || (letter === "k" && !shift)) return { action: "move", by: -1 }
  if (key === "PageDown") return { action: "move", by: 8 }
  if (key === "PageUp") return { action: "move", by: -8 }
  if (key === "Home") return { action: "move", to: "first" }
  if (key === "End") return { action: "move", to: "last" }
  if (key === "Backspace" || (letter === "h" && !shift)) return page === "detail" ? { action: "back" } : null

  if (key === "Return" || key === "Enter")
    return page === "list" && !shift ? { action: "openDetail" } : { action: "approve", quick: shift }
  if (letter === "a") return { action: "approve", quick: shift }
  if (letter === "d") return { action: "decline" }
  if (key === "Delete" || (letter === "x" && !shift)) return { action: "remove" }
  if (letter === "r") {
    if (!shift) return { action: "refresh" }
    return press.status === Requests.REQUEST_FAILED ? { action: "retry" } : null
  }
  if (letter === "o" && !shift) return { action: "open" }
  if (page === "detail" && letter === "w" && !shift) return { action: "watch" }
  if (page === "detail" && letter === "v" && !shift) return { action: "trailer" }
  if (page === "list") {
    if (text === "/") return { action: "focusSearch" }
    if (letter === "f") return { action: "cycle", key: "filter", values: Requests.FILTERS, backwards: shift }
    if (letter === "t") return { action: "cycle", key: "mediaType", values: Requests.MEDIA_TYPES, backwards: shift }
    if (letter === "s" && shift) return { action: "cycle", key: "sort", values: Requests.SORTS, backwards: false }
    if (letter === "i" && !shift) return { action: "cycle", key: "sortDirection", values: Requests.DIRECTIONS, backwards: false }
  }
  if (letter === "s" && !shift) return { action: "settings" }
  return null
}
