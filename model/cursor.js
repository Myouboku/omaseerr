// The list's cursor: moving it, stepping from one request's details to the
// next, when to ask for the next page, and scrolling a row or a control into
// view. panel/PanelState.qml applies it.
.pragma library

// Rows from the end of the list at which the next page is asked for.
var LOAD_AHEAD = 3

// `index` kept on one of `count` rows (0 when there are none).
function clampIndex(index, count) {
  return Math.max(0, Math.min(count - 1, index))
}

// Moving down onto one of the last rows loads more.
function wantsMore(dy, index, count) {
  return dy > 0 && index >= count - LOAD_AHEAD
}

// Where stepping `dy` requests from the one on display (`detailId`) lands
// among `rows`, or -1 when it stays put. `fromCursor` says the request was
// opened from the list, at the cursor: when it is no longer in the list
// (just approved or declined under the pending filter), the next one now
// sits where it was, so stepping down lands on the cursor. A request opened
// some other way (a notification) that is not in the list has no
// neighbours: it stays put.
function stepTarget(rows, detailId, cursor, dy, fromCursor) {
  if (rows.length === 0) return -1
  var at = -1
  for (var i = 0; i < rows.length; i++) if (rows[i].id === detailId) at = i
  if (at === -1 && !fromCursor) return -1
  var next = at === -1
    ? clampIndex(dy > 0 ? cursor + dy - 1 : cursor + dy, rows.length)
    : clampIndex(at + dy, rows.length)
  return next === at ? -1 : next
}

// The row `to` ("first" or "last") names among `count` rows.
function endIndex(to, count) {
  return to === "last" ? Math.max(0, count - 1) : 0
}

// The scroll position (contentY) that shows an item at `y`, `height` tall,
// in a view `viewHeight` tall over content `contentHeight` tall: unchanged
// when the item shows already, else just enough to bring it in with
// `margin` around it, never past the content's ends.
function scrollToShow(contentY, viewHeight, contentHeight, y, height, margin) {
  if (y < contentY) return Math.max(0, y - margin)
  if (y + height > contentY + viewHeight)
    return Math.min(Math.max(0, contentHeight - viewHeight), y + height - viewHeight + margin)
  return contentY
}
