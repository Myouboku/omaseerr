// What is worth a notification: requests not announced yet, status changes,
// the state file that remembers both across restarts, and notification text
// the daemon cannot read as markup.
.pragma library
.import "values.js" as Values
.import "requests.js" as Requests

// Bounded memory of request ids already announced.
var MAX_SEEN = 1000

function newRequestIds(seen, pending) {
  var known = {}
  for (var i = 0; i < seen.length; i++) known[seen[i]] = true
  var out = []
  for (var j = 0; j < pending.length; j++) if (!known[pending[j].id]) out.push(pending[j].id)
  return out
}

function rememberIds(seen, ids) {
  var set = {}
  var out = []
  var all = ids.concat(seen)
  for (var i = 0; i < all.length && out.length < MAX_SEEN; i++) {
    var id = Values.positiveId(all[i])
    if (id && !set[id]) { set[id] = true; out.push(id) }
  }
  return out
}

// Status transitions worth a notification: a request becoming available, or
// failing. `previous` is { id: statusKey }.
function statusChanges(previous, requests) {
  var out = []
  for (var i = 0; i < requests.length; i++) {
    var r = requests[i]
    var before = previous[r.id]
    var now = Requests.statusKey(r)
    if (before === undefined || before === now) continue
    if (now === "available" || now === "failed") out.push({ id: r.id, from: before, to: now })
  }
  return out
}

function statusMap(requests, keep) {
  var out = {}
  var n = 0
  for (var i = 0; i < requests.length && n < (keep || 200); i++) { out[requests[i].id] = Requests.statusKey(requests[i]); n++ }
  return out
}

// The Omarchy daemon renders a notification body as restricted markup, and it
// decodes entities (several passes) before deciding what is a tag, so plain
// escaping is undone. A word joiner after every "<" and "&" breaks any tag or
// entity Seerr text might carry while still reading the same on screen.
function neutralizeMarkup(text) {
  return String(text || "").replace(/</g, "<\u2060").replace(/&/g, "&\u2060")
}

// Persisted state: { url, seen: [ids], statuses: {id: key}, primed }.
function parseState(text) {
  var parsed = Values.parseJson(String(text || ""))
  var v = parsed.ok && parsed.value && typeof parsed.value === "object" ? parsed.value : {}
  var statuses = {}
  if (v.statuses && typeof v.statuses === "object") {
    var n = 0
    for (var k in v.statuses) {
      if (n++ >= 500) break
      var id = Values.positiveId(k)
      if (id && typeof v.statuses[k] === "string") statuses[id] = Values.str(v.statuses[k], 20)
    }
  }
  return {
    url: Values.str(v.url, 2048),
    seen: rememberIds([], Array.isArray(v.seen) ? v.seen.slice(0, MAX_SEEN) : []),
    statuses: statuses,
    primed: v.primed === true
  }
}
