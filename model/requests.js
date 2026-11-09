// Requests as the panel sees them: Seerr's statuses and what they mean to a
// person, the list's filters and sorts, merging pages, and seasons.
.pragma library

// Seerr's own enums (server/constants/media.ts).
var REQUEST_PENDING = 1
var REQUEST_APPROVED = 2
var REQUEST_DECLINED = 3
var REQUEST_FAILED = 4
var REQUEST_COMPLETED = 5

var MEDIA_UNKNOWN = 1
var MEDIA_PENDING = 2
var MEDIA_PROCESSING = 3
var MEDIA_PARTIALLY_AVAILABLE = 4
var MEDIA_AVAILABLE = 5
var MEDIA_BLOCKLISTED = 6
var MEDIA_DELETED = 7

// The filters the panel offers. Each maps to one of Seerr's `filter` values
// (Api.API_FILTER); `declined` has no server-side filter, so it lists
// everything and keeps the declined rows client-side.
var FILTERS = ["pending", "approved", "processing", "available", "failed", "declined", "all"]
var MEDIA_TYPES = ["all", "movie", "tv"]
var SORTS = ["added", "modified"]
var DIRECTIONS = ["desc", "asc"]

// ------------------------------------------------------------------ statuses

// One word for what a request means to a person, from the request status and
// the media's availability (4K requests read the 4K availability).
function statusKey(req) {
  if (!req) return "unknown"
  switch (req.status) {
  case REQUEST_PENDING: return "pending"
  case REQUEST_DECLINED: return "declined"
  case REQUEST_FAILED: return "failed"
  case REQUEST_COMPLETED:
    return req.mediaStatus === MEDIA_DELETED ? "deleted" : (req.mediaStatus === MEDIA_AVAILABLE ? "available" : "completed")
  case REQUEST_APPROVED:
    if (req.mediaStatus === MEDIA_AVAILABLE) return "available"
    if (req.mediaStatus === MEDIA_PARTIALLY_AVAILABLE) return "partial"
    if (req.mediaStatus === MEDIA_DELETED) return "deleted"
    return "processing"
  }
  return "unknown"
}

// Color of a status, taken from Seerr's own badges (Tailwind: success
// green-500, primary indigo-500, danger red-600). Waiting for a decision is the
// normal state, so it stays neutral (Seerr shows it yellow); "" means the
// panel's neutral text color, "dim" its muted one.
var STATUS_COLORS = {
  pending: "",
  processing: "#6366f1",
  partial: "#22c55e",
  available: "#22c55e",
  completed: "#22c55e",
  declined: "#dc2626",
  failed: "#dc2626",
  deleted: "#dc2626",
  unknown: "dim"
}

function statusColor(key) {
  return STATUS_COLORS.hasOwnProperty(key) ? STATUS_COLORS[key] : "dim"
}

// ------------------------------------------------------------------ list view

function matchesView(req, view, media) {
  if (!req) return false
  if (view.filter === "declined" && req.status !== REQUEST_DECLINED) return false
  var search = String(view.search || "").trim().toLowerCase()
  if (search !== "") {
    var hay = ((media && media.title) || "") + " " + ((media && media.year) || "") + " " + (req.requestedBy ? req.requestedBy.name : "")
    var words = search.split(/\s+/)
    hay = hay.toLowerCase()
    for (var i = 0; i < words.length; i++) if (hay.indexOf(words[i]) === -1) return false
  }
  return true
}

// Keeps the server's order (it already sorted), merging a fresh page into the
// rows already shown without duplicates.
function mergePage(existing, page) {
  var seen = {}
  var out = []
  for (var i = 0; i < existing.length; i++) { seen[existing[i].id] = true; out.push(existing[i]) }
  for (var j = 0; j < page.length; j++) if (!seen[page[j].id]) { seen[page[j].id] = true; out.push(page[j]) }
  return out
}

function replaceRequest(list, updated) {
  var out = []
  for (var i = 0; i < list.length; i++) out.push(list[i].id === updated.id ? updated : list[i])
  return out
}

function removeRequest(list, id) {
  return list.filter(function(r) { return r.id !== id })
}

// ------------------------------------------------------------------ seasons

function seasonsLabel(seasons) {
  if (!seasons || seasons.length === 0) return ""
  // Runs collapse: 1, 2, 3, 5 -> "1-3, 5".
  var parts = []
  var start = seasons[0], prev = seasons[0]
  for (var i = 1; i <= seasons.length; i++) {
    var cur = seasons[i]
    if (cur === prev + 1) { prev = cur; continue }
    parts.push(start === prev ? String(start) : start + "–" + prev)
    start = prev = cur
  }
  return parts.join(", ")
}
