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

// Statuses after which no notification can follow: nothing left to watch.
var SETTLED = ["available", "completed", "declined", "deleted"]
var MAX_STATUSES = 500

// `previous` updated with `requests` (the recently modified ones): a request
// that drops out of that recent window keeps its last status, so its later
// change is still noticed. Settled requests are dropped, and the newest ids
// are kept when there are too many.
function mergeStatuses(previous, requests) {
  var all = {}
  for (var k in previous) all[k] = previous[k]
  for (var i = 0; i < requests.length; i++) all[requests[i].id] = Requests.statusKey(requests[i])
  var ids = []
  for (var id in all) if (SETTLED.indexOf(all[id]) === -1) ids.push(Number(id))
  ids.sort(function(a, b) { return b - a })
  var out = {}
  for (var j = 0; j < ids.length && j < MAX_STATUSES; j++) out[ids[j]] = all[ids[j]]
  return out
}

// The Omarchy daemon renders a notification body as restricted markup, and it
// decodes entities (several passes) before deciding what is a tag, so plain
// escaping is undone. A word joiner after every "<" and "&" breaks any tag or
// entity Seerr text might carry while still reading the same on screen.
function neutralizeMarkup(text) {
  return String(text || "").replace(/</g, "<\u2060").replace(/&/g, "&\u2060")
}

// A lone surrogate cannot be written as UTF-8, so the sender would refuse the
// whole notification; it becomes U+FFFD instead.
function wellFormed(text) {
  return String(text || "").replace(/[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(^|[^\uD800-\uDBFF])[\uDC00-\uDFFF]/g,
    function(m, before) { return (before || "") + "�" })
}

var URGENCIES = { low: 0, normal: 1, critical: 2 }

// What service/dbus-notify.pl sends on the bus, from
// { app, summary, body, glyph, image, urgency: "low"|"normal"|"critical",
//   actions: [{ label, argv }], with: [args], exec: [argv] }:
// the same hints omarchy-notification-send would set. `with` is appended to
// every action's argv, and the card's own click runs the first action, or
// `exec` when there are no actions. The body is neutralised here.
function notification(spec) {
  spec = spec || {}
  var hints = {}
  if (spec.glyph) hints["omarchy-glyph"] = String(spec.glyph)
  if (spec.image) hints["image-path"] = wellFormed(spec.image)
  var withArgs = (spec["with"] || []).map(wellFormed)
  var actions = (spec.actions || []).slice(0, 3).map(function(a) {
    return { label: wellFormed(a.label), argv: (a.argv || []).map(wellFormed).concat(withArgs) }
  })
  if (actions.length) {
    hints["omarchy-actions"] = JSON.stringify(actions)
    hints["omarchy-exec-argv"] = JSON.stringify(actions[0].argv)
  } else if (spec.exec && spec.exec.length) {
    hints["omarchy-exec-argv"] = JSON.stringify(spec.exec.map(wellFormed))
  }
  return {
    app: wellFormed(spec.app),
    summary: wellFormed(spec.summary),
    body: wellFormed(neutralizeMarkup(spec.body)),
    urgency: URGENCIES.hasOwnProperty(spec.urgency) ? URGENCIES[spec.urgency] : 1,
    timeout: -1,
    hints: hints
  }
}

// Persisted state: { url, seen: [ids], statuses: {id: key}, primed,
// tracking }. `tracking` says the statuses were kept up to date until now;
// when they were not (status notifications were off), the first comparison
// only records, rather than announcing changes from long ago.
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
    primed: v.primed === true,
    tracking: v.tracking === true
  }
}
