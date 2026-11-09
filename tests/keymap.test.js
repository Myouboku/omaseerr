// Tests for model/keymap.js.

const { load, test, eq } = require("./harness")
const Requests = load("model/requests.js")
const KeyMap = load("model/keymap.js")

// A key press on the list's own keys, with `over` changing the situation.
function press(over) {
  return KeyMap.keyAction(Object.assign({ key: "", text: "", shift: false, page: "list", confirmOpen: false,
    inControl: false, searchFocused: false, searching: false, rowCount: 5, status: Requests.REQUEST_PENDING }, over))
}

test("the confirmation question takes every key first", () => {
  for (const page of ["list", "detail", "approve", "settings"]) {
    eq(press({ page, confirmOpen: true, key: "Escape" }), { action: "confirm" })
    eq(press({ page, confirmOpen: true, text: "a" }), { action: "confirm" })
  }
})

test("Escape leaves a control on the list and the form, else goes back", () => {
  eq(press({ key: "Escape" }), { action: "back" })
  eq(press({ key: "Escape", inControl: true }), { action: "leaveControl", clearSearch: false })
  eq(press({ key: "Escape", inControl: true, searchFocused: true }), { action: "leaveControl", clearSearch: false })
  // Leaving the search field with a search typed clears it.
  eq(press({ key: "Escape", inControl: true, searchFocused: true, searching: true }), { action: "leaveControl", clearSearch: true })
  eq(press({ page: "approve", key: "Escape", inControl: true, searchFocused: true, searching: true }), { action: "leaveControl", clearSearch: false })
  eq(press({ page: "approve", key: "Escape" }), { action: "back" })
  eq(press({ page: "detail", key: "Escape", inControl: true }), { action: "back" })
  eq(press({ page: "settings", key: "Escape", inControl: true }), { action: "back" })
})

test("the settings and the form keep typed keys for their fields", () => {
  for (const page of ["settings", "approve"]) {
    for (const text of ["a", "A", "d", "x", "j", "k", "h", "o", "r", "s", "/", "f"]) eq(press({ page, text }), null)
    for (const key of ["Down", "Up", "Home", "End", "PageDown", "Backspace", "Delete"]) eq(press({ page, key }), null)
  }
  eq(press({ page: "settings", key: "Return" }), null)
  eq(press({ page: "approve", key: "Return" }), { action: "submit", quick: false })
  eq(press({ page: "approve", key: "Enter", shift: true }), { action: "submit", quick: true })
})

test("moving: arrows, vi keys, pages, ends", () => {
  eq(press({ key: "Down" }), { action: "move", by: 1 })
  eq(press({ text: "j" }), { action: "move", by: 1 })
  eq(press({ key: "Up" }), { action: "move", by: -1 })
  eq(press({ text: "k" }), { action: "move", by: -1 })
  eq(press({ key: "PageDown" }), { action: "move", by: 8 })
  eq(press({ key: "PageUp" }), { action: "move", by: -8 })
  eq(press({ key: "Home", rowCount: 12 }), { action: "move", by: -12 })
  eq(press({ key: "End", rowCount: 12 }), { action: "move", by: 12 })
  eq(press({ page: "detail", key: "Down" }), { action: "move", by: 1 })
  // Down from the search field goes back to the rows instead.
  eq(press({ key: "Down", searchFocused: true, inControl: true }), { action: "leaveControl", clearSearch: false })
  eq(press({ key: "Up", searchFocused: true, inControl: true }), { action: "move", by: -1 })
})

test("Backspace and h go back from the details only", () => {
  eq(press({ page: "detail", key: "Backspace" }), { action: "back" })
  eq(press({ page: "detail", text: "h" }), { action: "back" })
  eq(press({ key: "Backspace" }), null)
  eq(press({ text: "h" }), null)
})

test("Enter opens on the list, approves elsewhere; Shift approves straight away", () => {
  eq(press({ key: "Return" }), { action: "openDetail" })
  eq(press({ key: "Enter" }), { action: "openDetail" })
  eq(press({ key: "Return", shift: true }), { action: "approve", quick: true })
  eq(press({ page: "detail", key: "Return" }), { action: "approve", quick: false })
  eq(press({ page: "detail", key: "Enter", shift: true }), { action: "approve", quick: true })
})

test("request and panel actions", () => {
  for (const page of ["list", "detail"]) {
    eq(press({ page, text: "a" }), { action: "approve", quick: false })
    eq(press({ page, text: "A", shift: true }), { action: "approve", quick: true })
    eq(press({ page, text: "d" }), { action: "decline" })
    eq(press({ page, text: "D" }), { action: "decline" })
    eq(press({ page, text: "x" }), { action: "remove" })
    eq(press({ page, key: "Delete" }), { action: "remove" })
    eq(press({ page, text: "o" }), { action: "open" })
    eq(press({ page, text: "r" }), { action: "refresh" })
    eq(press({ page, text: "s" }), { action: "settings" })
  }
})

test("R retries a failed request only", () => {
  eq(press({ text: "R", status: Requests.REQUEST_FAILED }), { action: "retry" })
  eq(press({ page: "detail", text: "R", status: Requests.REQUEST_FAILED }), { action: "retry" })
  eq(press({ text: "R", status: Requests.REQUEST_PENDING }), null)
  eq(press({ text: "R", status: 0 }), null)
})

test("the list's own keys: search and the view", () => {
  eq(press({ text: "/" }), { action: "focusSearch" })
  eq(press({ text: "f" }), { action: "cycle", key: "filter", values: Requests.FILTERS, backwards: false })
  eq(press({ text: "F", shift: true }), { action: "cycle", key: "filter", values: Requests.FILTERS, backwards: true })
  eq(press({ text: "t" }), { action: "cycle", key: "mediaType", values: Requests.MEDIA_TYPES, backwards: false })
  eq(press({ text: "T", shift: true }), null)
  eq(press({ text: "S", shift: true }), { action: "cycle", key: "sort", values: Requests.SORTS, backwards: false })
  eq(press({ text: "i" }), { action: "cycle", key: "sortDirection", values: Requests.DIRECTIONS, backwards: false })
  for (const text of ["/", "f", "F", "t", "S", "i"]) eq(press({ page: "detail", text }), null)
})

test("unknown keys are left alone", () => {
  eq(press({ text: "z" }), null)
  eq(press({ text: "" }), null)
  eq(press({ key: "Tab" }), null)
  eq(press({ page: "detail", text: "q" }), null)
})
