// Reading untrusted values: bounded plain strings, integers, ids, dates and
// JSON. Everything Seerr (or a file, or IPC) hands over goes through these.
.pragma library

var MAX_STRING = 512
var MAX_RESPONSE = 4 * 1024 * 1024

function str(value, max) {
  if (value === undefined || value === null) return ""
  var s = typeof value === "string" ? value : (typeof value === "number" || typeof value === "boolean" ? String(value) : "")
  // Controls other than tab/newline never belong in a title or a name.
  s = s.replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, "")
  var limit = max || MAX_STRING
  return s.length > limit ? s.slice(0, limit - 1) + "…" : s
}

function int(value, fallback) {
  var n = typeof value === "number" ? value : (typeof value === "string" && /^-?\d+$/.test(value) ? parseInt(value, 10) : NaN)
  if (!isFinite(n) || Math.floor(n) !== n || Math.abs(n) > 2147483647) return fallback === undefined ? 0 : fallback
  return n
}

function positiveId(value) {
  var n = int(value, 0)
  return n > 0 ? n : 0
}

function bool(value) {
  return value === true
}

function time(value) {
  if (typeof value !== "string" || value.length > 64) return 0
  var t = Date.parse(value)
  return isFinite(t) ? t : 0
}

function clampInt(value, fallback, min, max) {
  var n = parseInt(String(value), 10)
  if (!isFinite(n)) n = fallback
  if (n < min) n = min
  if (n > max) n = max
  return n
}

function oneOf(value, allowed, fallback) {
  var s = String(value === undefined || value === null ? "" : value)
  return allowed.indexOf(s) !== -1 ? s : fallback
}

function parseJson(text) {
  if (typeof text !== "string" || text.length === 0) return { ok: true, value: null }
  if (text.length > MAX_RESPONSE) return { ok: false, value: null, error: "tooLarge" }
  try {
    return { ok: true, value: JSON.parse(text) }
  } catch (e) {
    return { ok: false, value: null, error: "badJson" }
  }
}
