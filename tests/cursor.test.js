// Tests for model/cursor.js.

const { load, test, eq } = require("./harness")
const Cursor = load("model/cursor.js")

const rows = n => Array.from({ length: n }, (_, i) => ({ id: 100 + i }))

test("clampIndex keeps the cursor on a row", () => {
  eq(Cursor.clampIndex(3, 5), 3)
  eq(Cursor.clampIndex(-2, 5), 0)
  eq(Cursor.clampIndex(9, 5), 4)
  eq(Cursor.clampIndex(4, 5), 4)
  eq(Cursor.clampIndex(0, 1), 0)
  eq(Cursor.clampIndex(3, 0), 0) // no rows: 0, never -1
})

test("wantsMore when moving down onto the last three rows", () => {
  eq(Cursor.wantsMore(1, 16, 20), false)
  eq(Cursor.wantsMore(1, 17, 20), true)
  eq(Cursor.wantsMore(8, 19, 20), true)
  eq(Cursor.wantsMore(-1, 19, 20), false)
  eq(Cursor.wantsMore(0, 19, 20), false)
  eq(Cursor.wantsMore(1, 0, 2), true)
})

test("stepTarget moves from the request on display", () => {
  const r = rows(5)
  eq(Cursor.stepTarget(r, 102, 2, 1), 3)
  eq(Cursor.stepTarget(r, 102, 2, -1), 1)
  // The cursor does not matter while the request is in the list.
  eq(Cursor.stepTarget(r, 102, 0, 1), 3)
  eq(Cursor.stepTarget(r, 100, 0, -8), -1) // already first
  eq(Cursor.stepTarget(r, 104, 4, 1), -1) // already last
  eq(Cursor.stepTarget(r, 101, 1, 8), 4)
  eq(Cursor.stepTarget(r, 103, 3, -5), 0) // Home
  eq(Cursor.stepTarget(r, 101, 1, 5), 4) // End
  eq(Cursor.stepTarget([], 100, 0, 1), -1)
})

test("stepTarget after the request left the list: the next one is at the cursor", () => {
  // 102 was at index 2, then approved under the pending filter: what was
  // 103 now sits at index 2.
  const after = [{ id: 100 }, { id: 101 }, { id: 103 }, { id: 104 }]
  eq(Cursor.stepTarget(after, 102, 2, 1, true), 2)
  eq(Cursor.stepTarget(after, 102, 2, -1, true), 1)
  eq(Cursor.stepTarget(after, 102, 2, 8, true), 3)
  eq(Cursor.stepTarget(after, 102, 2, -8, true), 0)
  // It was the last one: down stays on the new last one.
  eq(Cursor.stepTarget([{ id: 100 }, { id: 101 }], 102, 2, 1, true), 1)
  // The cursor went out of range: clamped.
  eq(Cursor.stepTarget(after, 999, 10, -1, true), 3)
  eq(Cursor.stepTarget([{ id: 100 }], 102, 0, 1, true), 0)
  eq(Cursor.stepTarget([{ id: 100 }], 102, 0, -1, true), 0)
})

test("stepTarget from a request opened elsewhere and not in the list stays put", () => {
  // Opened from a notification: the cursor says nothing about where it was.
  const r = rows(5)
  eq(Cursor.stepTarget(r, 900, 3, 1, false), -1)
  eq(Cursor.stepTarget(r, 900, 3, -1, false), -1)
  // In the list, it steps from where it is, whatever the cursor.
  eq(Cursor.stepTarget(r, 101, 4, 1, false), 2)
})

test("endIndex names the first and last rows", () => {
  eq(Cursor.endIndex("first", 5), 0)
  eq(Cursor.endIndex("last", 5), 4)
  eq(Cursor.endIndex("last", 0), 0)
})


test("stepTarget uses the last row with the id", () => {
  eq(Cursor.stepTarget([{ id: 7 }, { id: 8 }, { id: 7 }, { id: 9 }], 7, 0, 1), 3)
})

test("scrollToShow scrolls just enough, within the content", () => {
  // view 100 tall at 200 over content 1000 tall, margin 6
  eq(Cursor.scrollToShow(200, 100, 1000, 220, 30, 6), 200) // shows already
  eq(Cursor.scrollToShow(200, 100, 1000, 200, 100, 6), 200) // exactly fits
  eq(Cursor.scrollToShow(200, 100, 1000, 150, 30, 6), 144) // above
  eq(Cursor.scrollToShow(200, 100, 1000, 3, 30, 6), 0) // above, near the top
  eq(Cursor.scrollToShow(200, 100, 1000, 290, 30, 6), 226) // below
  eq(Cursor.scrollToShow(200, 100, 1000, 960, 40, 6), 900) // below, near the end
  eq(Cursor.scrollToShow(0, 100, 50, 60, 30, 6), 0) // content shorter than the view
  eq(Cursor.scrollToShow(200, 100, 1000, 190, 200, 6), 184) // taller than the view: top first
})
