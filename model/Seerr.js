// Everything about Seerr that can be decided without the network or QML:
// URL handling, bounding and normalising API payloads, statuses, filtering
// and sorting, what counts as new, and the approval form. Pure functions only,
// so tests/run.js can load this file as-is under node.
.pragma library

var PLUGIN_ID = "myouboku.omaseerr"
var API_PREFIX = "/api/v1"

var MAX_STRING = 512
var MAX_OVERVIEW = 2000
var MAX_LIST = 200
var MAX_SEASONS = 100
var MAX_TAGS = 50
var MAX_RESPONSE = 4 * 1024 * 1024

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

// TMDB keyword Seerr uses to route a series to the anime profile.
var ANIME_KEYWORD_ID = 210024

// The filters the panel offers. Each maps to one of Seerr's `filter` values;
// `declined` has no server-side filter, so it lists everything and keeps the
// declined rows client-side.
var FILTERS = ["pending", "approved", "processing", "available", "failed", "declined", "all"]
var MEDIA_TYPES = ["all", "movie", "tv"]
var SORTS = ["added", "modified"]
var DIRECTIONS = ["desc", "asc"]

var API_FILTER = {
  pending: "pending",
  approved: "approved",
  processing: "processing",
  available: "available",
  failed: "failed",
  declined: "all",
  all: "all"
}

// ------------------------------------------------------------------ basics

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

// ------------------------------------------------------------------ URLs

// Accepts what people paste: with or without scheme, a trailing slash, or the
// /api/v1 suffix. http and https are both fine; anything else is refused.
// Returns { ok, url, secure, error } where url has no trailing slash.
function normalizeBaseUrl(raw) {
  var s = String(raw === undefined || raw === null ? "" : raw).trim()
  if (s === "") return { ok: false, url: "", secure: false, error: "empty" }
  if (s.length > 2048 || /[\s<>"'`\\]/.test(s) || /[\u0000-\u001f\u007f]/.test(s)) return { ok: false, url: "", secure: false, error: "invalid" }
  if (!/^[a-z][a-z0-9+.-]*:\/\//i.test(s)) s = "https://" + s
  var m = s.match(/^(https?):\/\/([^/?#]+)([^?#]*)(.*)$/i)
  if (!m) return { ok: false, url: "", secure: false, error: "scheme" }
  if (m[4] !== "") return { ok: false, url: "", secure: false, error: "invalid" }
  var scheme = m[1].toLowerCase()
  var authority = m[2]
  if (authority.indexOf("@") !== -1) return { ok: false, url: "", secure: false, error: "invalid" }
  var hp = authority.match(/^(\[[0-9a-fA-F:.]+\]|[A-Za-z0-9.-]+)(?::(\d{1,5}))?$/)
  if (!hp) return { ok: false, url: "", secure: false, error: "invalid" }
  var host = hp[1].toLowerCase()
  if (host.charAt(0) !== "[" && (host.charAt(0) === "." || host.charAt(0) === "-" || host.indexOf("..") !== -1))
    return { ok: false, url: "", secure: false, error: "invalid" }
  if (hp[2] !== undefined) {
    var port = parseInt(hp[2], 10)
    if (port < 1 || port > 65535) return { ok: false, url: "", secure: false, error: "invalid" }
  }
  var path = m[3].replace(/\/+$/, "").replace(/\/api\/v1$/i, "").replace(/\/+$/, "")
  if (path !== "" && !/^(\/[A-Za-z0-9._~!$&'()*+,;=:@%-]+)+$/.test(path)) return { ok: false, url: "", secure: false, error: "invalid" }
  var url = scheme + "://" + host + (hp[2] !== undefined ? ":" + parseInt(hp[2], 10) : "") + path
  return { ok: true, url: url, secure: scheme === "https", error: "" }
}

// The origin (scheme, host, port) the API key is bound to in the keyring, so
// a key saved for one Seerr is never sent to another one the URL is later
// changed to. The path is left out (it does not change who receives the key)
// and so is the scheme's default port. "" when the URL is not usable.
function keyOrigin(raw) {
  var n = normalizeBaseUrl(raw)
  if (!n.ok) return ""
  var m = n.url.match(/^(https?):\/\/(\[[^\]]+\]|[^/:]+)(?::(\d+))?/)
  if (!m) return ""
  var port = m[3] === undefined || (m[1] === "https" && m[3] === "443") || (m[1] === "http" && m[3] === "80") ? "" : ":" + m[3]
  return m[1] + "://" + m[2] + port
}

// Loopback, RFC 1918 / link-local / CGNAT addresses and .local/.lan/.home
// names: places where plain HTTP is a reasonable choice.
function isPrivateHost(url) {
  var m = String(url || "").match(/^https?:\/\/(\[[^\]]+\]|[^/:]+)/i)
  if (!m) return false
  var h = m[1].toLowerCase()
  if (h === "localhost" || h === "[::1]" || /\.(local|lan|home|internal|localdomain)$/.test(h) || h.indexOf(".") === -1 && h.charAt(0) !== "[") return true
  if (/^\[f[cd][0-9a-f]{2}:/.test(h) || /^\[fe80:/.test(h)) return true
  var ip = h.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/)
  if (!ip) return false
  var a = +ip[1], b = +ip[2]
  return a === 127 || a === 10 || (a === 192 && b === 168) || (a === 172 && b >= 16 && b <= 31)
    || (a === 169 && b === 254) || (a === 100 && b >= 64 && b <= 127)
}

// The value of one setting given as text (from IPC), or undefined when the
// key is unknown or the value does not fit it.
function parseSettingValue(key, text) {
  if (!Object.prototype.hasOwnProperty.call(DEFAULTS, key)) return undefined
  var def = DEFAULTS[key]
  var s = String(text === undefined || text === null ? "" : text).trim()
  if (typeof def === "boolean") {
    if (/^(true|1|on|yes)$/i.test(s)) return true
    if (/^(false|0|off|no)$/i.test(s)) return false
    return undefined
  }
  if (typeof def === "number") return /^\d+$/.test(s) ? parseInt(s, 10) : undefined
  if (key === "url") {
    if (s === "") return ""
    var u = normalizeBaseUrl(s)
    return u.ok ? u.url : undefined
  }
  var probe = {}
  probe[key] = s
  return normalizeSettings(probe)[key] === s ? s : undefined
}

function query(params) {
  var parts = []
  for (var k in params) {
    var v = params[k]
    if (v === undefined || v === null || v === "") continue
    parts.push(encodeURIComponent(k) + "=" + encodeURIComponent(String(v)))
  }
  return parts.length ? "?" + parts.join("&") : ""
}

// The list query for a panel view. `take` asks for a little more than a page
// when the declined filter has to be applied client-side.
function listPath(opts) {
  var filter = oneOf(opts.filter, FILTERS, "pending")
  var take = clampInt(opts.take, 20, 1, 100)
  return "/request" + query({
    take: take,
    skip: Math.max(0, int(opts.skip, 0)),
    filter: API_FILTER[filter],
    sort: oneOf(opts.sort, SORTS, "added"),
    sortDirection: oneOf(opts.sortDirection, DIRECTIONS, "desc"),
    mediaType: oneOf(opts.mediaType, MEDIA_TYPES, "all"),
    requestedBy: positiveId(opts.requestedBy) || undefined
  })
}

function mediaPath(type, tmdbId) {
  var id = positiveId(tmdbId)
  if (!id) return ""
  return (type === "tv" ? "/tv/" : "/movie/") + id
}

function webUrl(baseUrl, type, tmdbId) {
  var id = positiveId(tmdbId)
  if (!baseUrl || !id) return baseUrl || ""
  return baseUrl + (type === "tv" ? "/tv/" : "/movie/") + id
}

// TMDB poster paths look like "/abc123.jpg". Anything else is dropped rather
// than fetched, so a hostile payload cannot steer the image loader.
function safeImagePath(value) {
  var s = typeof value === "string" ? value : ""
  return /^\/[A-Za-z0-9_-]{1,64}\.(jpg|jpeg|png|webp)$/.test(s) ? s : ""
}

function posterUrl(path, size) {
  var p = safeImagePath(path)
  if (!p) return ""
  var w = oneOf(size, ["w92", "w154", "w185", "w342"], "w185")
  return "https://image.tmdb.org/t/p/" + w + p
}

// ------------------------------------------------------------------ HTTP via curl

// API calls go through curl rather than QML's XMLHttpRequest, which follows
// redirects on its own and re-sends every header, X-Api-Key included, to
// wherever the server points. curl follows none (no -L), so the key only ever
// reaches the URL it was bound to. Everything secret travels in a config file
// on stdin (-K -), never in argv where /proc would show it. -q, which must
// come first, keeps a ~/.curlrc (and its possible -L) out of it.
var CURL_MARK = "\n@@omaseerr-curl@@ "

function curlArgv(timeoutSec) {
  var t = String(clampInt(timeoutSec, 15, 1, 120))
  return ["curl", "-q", "--silent", "--globoff", "--proto", "=http,https",
    "--connect-timeout", "10", "--max-time", t, "--max-filesize", String(MAX_RESPONSE),
    "--compressed", "--config", "-"]
}

// A curl config string: quoted, with the escapes curl's config parser knows.
function curlQuote(value) {
  return "\"" + String(value)
    .replace(/\\/g, "\\\\").replace(/"/g, "\\\"")
    .replace(/\n/g, "\\n").replace(/\r/g, "\\r").replace(/\t/g, "\\t") + "\""
}

function curlConfig(method, url, key, body) {
  var lines = [
    "url = " + curlQuote(url),
    "request = " + curlQuote(method),
    "header = " + curlQuote("X-Api-Key: " + key),
    "header = " + curlQuote("Accept: application/json"),
    // The status and any redirect target, after the body.
    "write-out = " + curlQuote(CURL_MARK + "%{http_code} %{redirect_url}")
  ]
  if (body !== null && body !== undefined) {
    lines.push("header = " + curlQuote("Content-Type: application/json"))
    // data-raw, unlike data, never reads a file for a leading "@".
    lines.push("data-raw = " + curlQuote(JSON.stringify(body)))
  }
  return lines.join("\n") + "\n"
}

// curl exit codes worth telling apart; anything else is "network".
var CURL_TLS_CODES = [35, 51, 53, 54, 58, 59, 60, 64, 66, 77, 80, 82, 83, 90, 91, 98]

// The { ok, status, data, error, message, location } an API callback gets,
// from curl's exit code and output.
function parseCurlResult(exitCode, output) {
  var code = typeof exitCode === "number" ? exitCode : -1
  if (code === 28) return { ok: false, status: 0, error: "timeout" }
  if (code === 63) return { ok: false, status: 0, error: "tooLarge" }
  if (CURL_TLS_CODES.indexOf(code) !== -1) return { ok: false, status: 0, error: "tls" }
  var out = typeof output === "string" ? output : ""
  var at = out.lastIndexOf(CURL_MARK)
  if (code !== 0 || at === -1) return { ok: false, status: 0, error: "network" }
  var tail = out.slice(at + CURL_MARK.length).replace(/\s+$/, "")
  var m = tail.match(/^(\d{3})(?: ([^\n]*))?$/)
  var status = m ? parseInt(m[1], 10) : 0
  if (status === 0) return { ok: false, status: 0, error: "network" }
  if (status >= 300 && status < 400) {
    // Shown as the address to use instead, so without the API path.
    var location = str(m[2] || "", 300)
    var api = location.indexOf(API_PREFIX + "/")
    if (api > 0) location = location.slice(0, api)
    return { ok: false, status: status, error: "redirect", location: location }
  }
  var parsed = parseJson(out.slice(0, at))
  if (status >= 200 && status < 300)
    return parsed.ok ? { ok: true, status: status, data: parsed.value } : { ok: false, status: status, error: parsed.error }
  return { ok: false, status: status, error: "http", message: parsed.ok ? errorMessage(parsed.value) : "" }
}

// ------------------------------------------------------------------ payloads

function parseJson(text) {
  if (typeof text !== "string" || text.length === 0) return { ok: true, value: null }
  if (text.length > MAX_RESPONSE) return { ok: false, value: null, error: "tooLarge" }
  try {
    return { ok: true, value: JSON.parse(text) }
  } catch (e) {
    return { ok: false, value: null, error: "badJson" }
  }
}

// Seerr answers errors as { message } (and sometimes { error }).
function errorMessage(value) {
  if (!value || typeof value !== "object") return ""
  return str(value.message || value.error || "", 300)
}

function normalizeUser(raw) {
  if (!raw || typeof raw !== "object") return null
  var id = positiveId(raw.id)
  if (!id) return null
  var name = str(raw.displayName || raw.username || raw.plexUsername || raw.jellyfinUsername || raw.email || "", 120)
  return { id: id, name: name || ("#" + id) }
}

function normalizeRequest(raw) {
  if (!raw || typeof raw !== "object") return null
  var id = positiveId(raw.id)
  if (!id) return null
  var media = raw.media && typeof raw.media === "object" ? raw.media : {}
  var type = raw.type === "tv" || media.mediaType === "tv" ? "tv" : "movie"
  var seasons = []
  if (Array.isArray(raw.seasons)) {
    for (var i = 0; i < raw.seasons.length && seasons.length < MAX_SEASONS; i++) {
      var s = raw.seasons[i]
      var n = s && typeof s === "object" ? int(s.seasonNumber, -1) : -1
      if (n >= 0 && seasons.indexOf(n) === -1) seasons.push(n)
    }
    seasons.sort(function(a, b) { return a - b })
  }
  var tags = []
  if (Array.isArray(raw.tags)) {
    for (var j = 0; j < raw.tags.length && tags.length < MAX_TAGS; j++) {
      var t = int(raw.tags[j], -1)
      if (t >= 0 && tags.indexOf(t) === -1) tags.push(t)
    }
  }
  var is4k = bool(raw.is4k)
  return {
    id: id,
    type: type,
    status: int(raw.status, 0),
    is4k: is4k,
    createdAt: time(raw.createdAt),
    updatedAt: time(raw.updatedAt),
    tmdbId: positiveId(media.tmdbId),
    tvdbId: positiveId(media.tvdbId),
    mediaStatus: int(is4k ? media.status4k : media.status, 0),
    requestedBy: normalizeUser(raw.requestedBy),
    modifiedBy: normalizeUser(raw.modifiedBy),
    seasons: seasons,
    serverId: raw.serverId === null || raw.serverId === undefined ? -1 : int(raw.serverId, -1),
    profileId: raw.profileId === null || raw.profileId === undefined ? -1 : int(raw.profileId, -1),
    rootFolder: str(raw.rootFolder || "", 1024),
    languageProfileId: raw.languageProfileId === null || raw.languageProfileId === undefined ? -1 : int(raw.languageProfileId, -1),
    tags: tags
  }
}

// { requests, total, pages } from a GET /request answer.
function normalizeRequestList(value) {
  var out = { requests: [], total: 0, pages: 0 }
  if (!value || typeof value !== "object") return out
  var results = Array.isArray(value.results) ? value.results : []
  for (var i = 0; i < results.length && out.requests.length < MAX_LIST; i++) {
    var r = normalizeRequest(results[i])
    if (r) out.requests.push(r)
  }
  var info = value.pageInfo && typeof value.pageInfo === "object" ? value.pageInfo : {}
  out.total = Math.max(0, int(info.results, out.requests.length))
  out.pages = Math.max(0, int(info.pages, 0))
  return out
}

function normalizeCounts(value) {
  var keys = ["total", "movie", "tv", "pending", "approved", "declined", "processing", "available", "completed"]
  var out = {}
  for (var i = 0; i < keys.length; i++)
    out[keys[i]] = value && typeof value === "object" ? Math.max(0, int(value[keys[i]], 0)) : 0
  return out
}

function yearOf(date) {
  var m = typeof date === "string" ? date.match(/^(\d{4})-/) : null
  return m ? m[1] : ""
}

function normalizeMedia(raw, type) {
  if (!raw || typeof raw !== "object") return null
  var isTv = type === "tv"
  var genres = []
  if (Array.isArray(raw.genres)) {
    for (var i = 0; i < raw.genres.length && genres.length < 8; i++) {
      var g = raw.genres[i]
      var name = g && typeof g === "object" ? str(g.name, 40) : ""
      if (name) genres.push(name)
    }
  }
  var seasons = []
  if (isTv && Array.isArray(raw.seasons)) {
    for (var j = 0; j < raw.seasons.length && seasons.length < MAX_SEASONS; j++) {
      var s = raw.seasons[j]
      if (!s || typeof s !== "object") continue
      var n = int(s.seasonNumber, -1)
      if (n < 0) continue
      seasons.push({ seasonNumber: n, name: str(s.name, 80), episodeCount: Math.max(0, int(s.episodeCount, 0)) })
    }
    seasons.sort(function(a, b) { return a.seasonNumber - b.seasonNumber })
  }
  var keywords = raw.keywords && Array.isArray(raw.keywords) ? raw.keywords
    : (raw.keywords && Array.isArray(raw.keywords.results) ? raw.keywords.results : [])
  var anime = false
  for (var k = 0; k < keywords.length && k < 100; k++)
    if (keywords[k] && int(keywords[k].id, 0) === ANIME_KEYWORD_ID) anime = true
  var date = isTv ? raw.firstAirDate : raw.releaseDate
  return {
    title: str(isTv ? (raw.name || raw.originalName) : (raw.title || raw.originalTitle), 200),
    year: yearOf(date),
    overview: str(raw.overview, MAX_OVERVIEW),
    posterPath: safeImagePath(raw.posterPath),
    runtime: isTv ? 0 : Math.max(0, int(raw.runtime, 0)),
    genres: genres,
    seasons: seasons,
    seasonCount: isTv ? Math.max(0, int(raw.numberOfSeasons, seasons.length)) : 0,
    anime: anime,
    vote: typeof raw.voteAverage === "number" && isFinite(raw.voteAverage) ? Math.round(raw.voteAverage * 10) / 10 : 0
  }
}

function mediaKey(type, tmdbId) {
  return (type === "tv" ? "tv:" : "movie:") + positiveId(tmdbId)
}

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

// ------------------------------------------------------------------ settings

var DEFAULTS = {
  url: "",
  refreshIntervalSec: 60,
  notifyNewRequests: true,
  notifyStatusChanges: false,
  notifyOnStartup: false,
  notifyUrgency: "normal",
  notifyPoster: true,
  notifyGroupThreshold: 3,
  defaultFilter: "pending",
  defaultMediaType: "all",
  defaultSort: "added",
  defaultSortDirection: "desc",
  pageSize: 20,
  showPosters: true,
  showBadge: true,
  badgeWhenEmpty: false,
  confirmDecline: true
}

// Every setting validated and clamped; unknown keys are dropped.
function normalizeSettings(raw) {
  var s = raw && typeof raw === "object" ? raw : {}
  var url = normalizeBaseUrl(s.url)
  return {
    url: url.ok ? url.url : "",
    refreshIntervalSec: clampInt(s.refreshIntervalSec, DEFAULTS.refreshIntervalSec, 15, 3600),
    notifyNewRequests: s.notifyNewRequests === undefined ? DEFAULTS.notifyNewRequests : s.notifyNewRequests === true,
    notifyStatusChanges: s.notifyStatusChanges === true,
    notifyOnStartup: s.notifyOnStartup === true,
    notifyUrgency: oneOf(s.notifyUrgency, ["low", "normal", "critical"], DEFAULTS.notifyUrgency),
    notifyPoster: s.notifyPoster === undefined ? DEFAULTS.notifyPoster : s.notifyPoster === true,
    notifyGroupThreshold: clampInt(s.notifyGroupThreshold, DEFAULTS.notifyGroupThreshold, 1, 20),
    defaultFilter: oneOf(s.defaultFilter, FILTERS, DEFAULTS.defaultFilter),
    defaultMediaType: oneOf(s.defaultMediaType, MEDIA_TYPES, DEFAULTS.defaultMediaType),
    defaultSort: oneOf(s.defaultSort, SORTS, DEFAULTS.defaultSort),
    defaultSortDirection: oneOf(s.defaultSortDirection, DIRECTIONS, DEFAULTS.defaultSortDirection),
    pageSize: clampInt(s.pageSize, DEFAULTS.pageSize, 5, 100),
    showPosters: s.showPosters === undefined ? DEFAULTS.showPosters : s.showPosters === true,
    showBadge: s.showBadge === undefined ? DEFAULTS.showBadge : s.showBadge === true,
    badgeWhenEmpty: s.badgeWhenEmpty === true,
    confirmDecline: s.confirmDecline === undefined ? DEFAULTS.confirmDecline : s.confirmDecline === true
  }
}

// This plugin's entry in the bar layout, wherever it was put.
function findBarEntry(barConfig, id) {
  var layout = barConfig && typeof barConfig === "object" && barConfig.layout && typeof barConfig.layout === "object" ? barConfig.layout : null
  if (!layout) return null
  for (var section in layout) {
    var list = layout[section]
    if (!Array.isArray(list)) continue
    for (var i = 0; i < list.length; i++) {
      var entry = list[i]
      if (entry && typeof entry === "object" && entry.id === id) return entry
      if (entry === id) return { id: id }
    }
  }
  return null
}

// ------------------------------------------------------------------ notifications

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
    var id = positiveId(all[i])
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
    var now = statusKey(r)
    if (before === undefined || before === now) continue
    if (now === "available" || now === "failed") out.push({ id: r.id, from: before, to: now })
  }
  return out
}

function statusMap(requests, keep) {
  var out = {}
  var n = 0
  for (var i = 0; i < requests.length && n < (keep || 200); i++) { out[requests[i].id] = statusKey(requests[i]); n++ }
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
  var parsed = parseJson(String(text || ""))
  var v = parsed.ok && parsed.value && typeof parsed.value === "object" ? parsed.value : {}
  var statuses = {}
  if (v.statuses && typeof v.statuses === "object") {
    var n = 0
    for (var k in v.statuses) {
      if (n++ >= 500) break
      var id = positiveId(k)
      if (id && typeof v.statuses[k] === "string") statuses[id] = str(v.statuses[k], 20)
    }
  }
  return {
    url: str(v.url, 2048),
    seen: rememberIds([], Array.isArray(v.seen) ? v.seen.slice(0, MAX_SEEN) : []),
    statuses: statuses,
    primed: v.primed === true
  }
}

// ------------------------------------------------------------------ approval

function normalizeServers(value) {
  var out = []
  if (!Array.isArray(value)) return out
  for (var i = 0; i < value.length && out.length < 20; i++) {
    var s = value[i]
    if (!s || typeof s !== "object") continue
    var id = int(s.id, -1)
    if (id < 0) continue
    out.push({
      id: id,
      name: str(s.name, 80) || ("#" + id),
      is4k: bool(s.is4k),
      isDefault: bool(s.isDefault),
      activeProfileId: int(s.activeProfileId, -1),
      activeDirectory: str(s.activeDirectory, 1024),
      activeLanguageProfileId: int(s.activeLanguageProfileId, -1),
      activeAnimeProfileId: int(s.activeAnimeProfileId, -1),
      activeAnimeDirectory: str(s.activeAnimeDirectory, 1024),
      activeAnimeLanguageProfileId: int(s.activeAnimeLanguageProfileId, -1),
      activeTags: idList(s.activeTags),
      activeAnimeTags: idList(s.activeAnimeTags)
    })
  }
  return out
}

function idList(value) {
  var out = []
  if (!Array.isArray(value)) return out
  for (var i = 0; i < value.length && out.length < MAX_TAGS; i++) {
    var n = int(value[i], -1)
    if (n >= 0 && out.indexOf(n) === -1) out.push(n)
  }
  return out
}

function namedList(value, labelKey) {
  var out = []
  if (!Array.isArray(value)) return out
  for (var i = 0; i < value.length && out.length < MAX_LIST; i++) {
    var v = value[i]
    if (!v || typeof v !== "object") continue
    var id = int(v.id, -1)
    if (id < 0) continue
    out.push({ id: id, name: str(v[labelKey || "name"], 200) || ("#" + id) })
  }
  return out
}

function normalizeServerDetails(value) {
  var v = value && typeof value === "object" ? value : {}
  var folders = []
  if (Array.isArray(v.rootFolders)) {
    for (var i = 0; i < v.rootFolders.length && folders.length < 50; i++) {
      var f = v.rootFolders[i]
      var path = f && typeof f === "object" ? str(f.path, 1024) : ""
      if (path) folders.push({ path: path, freeSpace: typeof f.freeSpace === "number" && isFinite(f.freeSpace) ? f.freeSpace : -1 })
    }
  }
  return {
    profiles: namedList(v.profiles, "name"),
    rootFolders: folders,
    languageProfiles: Array.isArray(v.languageProfiles) ? namedList(v.languageProfiles, "name") : null,
    tags: namedList(v.tags, "label")
  }
}

// The server Seerr itself would pick: the request's own, else the default for
// its 4K-ness, else the first of that 4K-ness.
function pickServer(servers, req) {
  var candidates = servers.filter(function(s) { return s.is4k === !!req.is4k })
  if (req.serverId >= 0) {
    for (var i = 0; i < servers.length; i++) if (servers[i].id === req.serverId) return servers[i]
  }
  for (var j = 0; j < candidates.length; j++) if (candidates[j].isDefault) return candidates[j]
  return candidates.length ? candidates[0] : null
}

// Initial approval form values, mirroring Seerr's advanced requester: the
// request's own choices first, then the server's (anime) defaults.
function defaultForm(req, server, details, anime) {
  var form = {
    serverId: server ? server.id : -1,
    profileId: -1,
    rootFolder: "",
    languageProfileId: -1,
    tags: [],
    seasons: req ? req.seasons.slice() : []
  }
  if (!server) return form
  var sameServer = req && req.serverId === server.id
  form.profileId = sameServer && req.profileId >= 0 ? req.profileId : (anime && server.activeAnimeProfileId >= 0 ? server.activeAnimeProfileId : server.activeProfileId)
  form.rootFolder = sameServer && req.rootFolder ? req.rootFolder : (anime && server.activeAnimeDirectory ? server.activeAnimeDirectory : server.activeDirectory)
  form.languageProfileId = sameServer && req.languageProfileId >= 0 ? req.languageProfileId
    : (anime && server.activeAnimeLanguageProfileId >= 0 ? server.activeAnimeLanguageProfileId : server.activeLanguageProfileId)
  form.tags = sameServer && req.tags.length ? req.tags.slice() : (anime ? server.activeAnimeTags.slice() : server.activeTags.slice())
  if (details) {
    if (!details.profiles.some(function(p) { return p.id === form.profileId }))
      form.profileId = details.profiles.length ? details.profiles[0].id : -1
    if (!details.rootFolders.some(function(f) { return f.path === form.rootFolder }))
      form.rootFolder = details.rootFolders.length ? details.rootFolders[0].path : ""
    if (details.languageProfiles && !details.languageProfiles.some(function(p) { return p.id === form.languageProfileId }))
      form.languageProfileId = details.languageProfiles.length ? details.languageProfiles[0].id : -1
    if (!details.languageProfiles) form.languageProfileId = -1
    var known = {}
    details.tags.forEach(function(t) { known[t.id] = true })
    form.tags = form.tags.filter(function(t) { return known[t] })
  }
  return form
}

// Why the form cannot be submitted yet, or "" when it can.
function formProblem(req, form) {
  if (!form || form.serverId < 0) return "noServer"
  if (form.profileId < 0) return "noProfile"
  if (!form.rootFolder) return "noRootFolder"
  if (req && req.type === "tv" && (!form.seasons || form.seasons.length === 0)) return "noSeasons"
  return ""
}

// Body of PUT /request/{id}. Seerr overwrites every field it is given and
// clears the ones left out, so all of them always go.
function updateBody(req, form) {
  var body = {
    mediaType: req.type,
    serverId: form.serverId,
    profileId: form.profileId,
    rootFolder: form.rootFolder,
    tags: form.tags.slice()
  }
  if (req.type === "tv") {
    body.seasons = form.seasons.slice().sort(function(a, b) { return a - b })
    if (form.languageProfileId >= 0) body.languageProfileId = form.languageProfileId
  }
  return body
}

function toggleInList(list, value) {
  var out = list.slice()
  var at = out.indexOf(value)
  if (at === -1) out.push(value)
  else out.splice(at, 1)
  out.sort(function(a, b) { return a - b })
  return out
}

// ------------------------------------------------------------------ display

// "3 min", "2 h", "5 d", or a date for anything older than a month. `words`
// carries the translated units: { now, minutes, hours, days } where each
// takes %1, plus `date(ms)` for old ones.
function relativeTime(ms, now, words) {
  if (!ms) return ""
  var diff = Math.max(0, (now || Date.now()) - ms)
  var minute = 60000, hour = 3600000, day = 86400000
  if (diff < minute) return words.now
  if (diff < hour) return words.minutes(Math.floor(diff / minute))
  if (diff < day) return words.hours(Math.floor(diff / hour))
  if (diff < 30 * day) return words.days(Math.floor(diff / day))
  return words.date(ms)
}

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

function formatBytes(bytes, formatNumber) {
  if (typeof bytes !== "number" || bytes < 0) return ""
  var units = ["B", "KB", "MB", "GB", "TB", "PB"]
  var v = bytes, u = 0
  while (v >= 1024 && u < units.length - 1) { v /= 1024; u++ }
  var fmt = formatNumber || function(x, d) { return x.toFixed(d) }
  return fmt(v, v >= 100 || u === 0 ? 0 : 1) + " " + units[u]
}
