// Talking about Seerr's API: the base URL people paste and the origin its key
// is bound to, request paths, links to the web UI and posters, and bounding
// and normalising what the API answers (requests, users, media, counts, the
// Radarr/Sonarr servers). Nothing here touches the network.
.pragma library
.import "values.js" as Values
.import "requests.js" as Requests

var API_PREFIX = "/api/v1"

var MAX_OVERVIEW = 2000
var MAX_LIST = 200
var MAX_SEASONS = 100
var MAX_TAGS = 50

// TMDB keyword Seerr uses to route a series to the anime profile.
var ANIME_KEYWORD_ID = 210024

// Seerr's `filter` value for each of the panel's filters (Requests.FILTERS).
var API_FILTER = {
  pending: "pending",
  approved: "approved",
  processing: "processing",
  available: "available",
  failed: "failed",
  declined: "all",
  all: "all"
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
  var filter = Values.oneOf(opts.filter, Requests.FILTERS, "pending")
  var take = Values.clampInt(opts.take, 20, 1, 100)
  return "/request" + query({
    take: take,
    skip: Math.max(0, Values.int(opts.skip, 0)),
    filter: API_FILTER[filter],
    sort: Values.oneOf(opts.sort, Requests.SORTS, "added"),
    sortDirection: Values.oneOf(opts.sortDirection, Requests.DIRECTIONS, "desc"),
    mediaType: Values.oneOf(opts.mediaType, Requests.MEDIA_TYPES, "all"),
    requestedBy: Values.positiveId(opts.requestedBy) || undefined
  })
}

// The request an IPC call or a notification button names: "42", or
// "42@https://seerr.example.com" when a notification also names the server it
// was about, so a button clicked after the URL changed cannot act on another
// Seerr's request of the same id. { id, origin } with id 0 when unusable.
function actionTarget(text) {
  var s = String(text === undefined || text === null ? "" : text).trim()
  var at = s.indexOf("@")
  var idPart = at === -1 ? s : s.slice(0, at)
  return { id: /^\d+$/.test(idPart) ? Values.positiveId(idPart) : 0, origin: at === -1 ? "" : s.slice(at + 1) }
}

function mediaPath(type, tmdbId) {
  var id = Values.positiveId(tmdbId)
  if (!id) return ""
  return (type === "tv" ? "/tv/" : "/movie/") + id
}

function webUrl(baseUrl, type, tmdbId) {
  var id = Values.positiveId(tmdbId)
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
  var w = Values.oneOf(size, ["w92", "w154", "w185", "w342"], "w185")
  return "https://image.tmdb.org/t/p/" + w + p
}

// ------------------------------------------------------------------ payloads

// Seerr answers errors as { message } (and sometimes { error }).
function errorMessage(value) {
  if (!value || typeof value !== "object") return ""
  return Values.str(value.message || value.error || "", 300)
}

function normalizeUser(raw) {
  if (!raw || typeof raw !== "object") return null
  var id = Values.positiveId(raw.id)
  if (!id) return null
  var name = Values.str(raw.displayName || raw.username || raw.plexUsername || raw.jellyfinUsername || raw.email || "", 120)
  return { id: id, name: name || ("#" + id) }
}

function normalizeRequest(raw) {
  if (!raw || typeof raw !== "object") return null
  var id = Values.positiveId(raw.id)
  if (!id) return null
  var media = raw.media && typeof raw.media === "object" ? raw.media : {}
  var type = raw.type === "tv" || media.mediaType === "tv" ? "tv" : "movie"
  var seasons = []
  if (Array.isArray(raw.seasons)) {
    for (var i = 0; i < raw.seasons.length && seasons.length < MAX_SEASONS; i++) {
      var s = raw.seasons[i]
      var n = s && typeof s === "object" ? Values.int(s.seasonNumber, -1) : -1
      if (n >= 0 && seasons.indexOf(n) === -1) seasons.push(n)
    }
    seasons.sort(function(a, b) { return a - b })
  }
  var tags = []
  if (Array.isArray(raw.tags)) {
    for (var j = 0; j < raw.tags.length && tags.length < MAX_TAGS; j++) {
      var t = Values.int(raw.tags[j], -1)
      if (t >= 0 && tags.indexOf(t) === -1) tags.push(t)
    }
  }
  var is4k = Values.bool(raw.is4k)
  return {
    id: id,
    type: type,
    status: Values.int(raw.status, 0),
    is4k: is4k,
    createdAt: Values.time(raw.createdAt),
    updatedAt: Values.time(raw.updatedAt),
    tmdbId: Values.positiveId(media.tmdbId),
    tvdbId: Values.positiveId(media.tvdbId),
    mediaStatus: Values.int(is4k ? media.status4k : media.status, 0),
    requestedBy: normalizeUser(raw.requestedBy),
    modifiedBy: normalizeUser(raw.modifiedBy),
    seasons: seasons,
    serverId: raw.serverId === null || raw.serverId === undefined ? -1 : Values.int(raw.serverId, -1),
    profileId: raw.profileId === null || raw.profileId === undefined ? -1 : Values.int(raw.profileId, -1),
    rootFolder: Values.str(raw.rootFolder || "", 1024),
    languageProfileId: raw.languageProfileId === null || raw.languageProfileId === undefined ? -1 : Values.int(raw.languageProfileId, -1),
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
  out.total = Math.max(0, Values.int(info.results, out.requests.length))
  out.pages = Math.max(0, Values.int(info.pages, 0))
  return out
}

function normalizeCounts(value) {
  var keys = ["total", "movie", "tv", "pending", "approved", "declined", "processing", "available", "completed"]
  var out = {}
  for (var i = 0; i < keys.length; i++)
    out[keys[i]] = value && typeof value === "object" ? Math.max(0, Values.int(value[keys[i]], 0)) : 0
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
      var name = g && typeof g === "object" ? Values.str(g.name, 40) : ""
      if (name) genres.push(name)
    }
  }
  var seasons = []
  if (isTv && Array.isArray(raw.seasons)) {
    for (var j = 0; j < raw.seasons.length && seasons.length < MAX_SEASONS; j++) {
      var s = raw.seasons[j]
      if (!s || typeof s !== "object") continue
      var n = Values.int(s.seasonNumber, -1)
      if (n < 0) continue
      seasons.push({ seasonNumber: n, name: Values.str(s.name, 80), episodeCount: Math.max(0, Values.int(s.episodeCount, 0)) })
    }
    seasons.sort(function(a, b) { return a.seasonNumber - b.seasonNumber })
  }
  var keywords = raw.keywords && Array.isArray(raw.keywords) ? raw.keywords
    : (raw.keywords && Array.isArray(raw.keywords.results) ? raw.keywords.results : [])
  var anime = false
  for (var k = 0; k < keywords.length && k < 100; k++)
    if (keywords[k] && Values.int(keywords[k].id, 0) === ANIME_KEYWORD_ID) anime = true
  var date = isTv ? raw.firstAirDate : raw.releaseDate
  return {
    title: Values.str(isTv ? (raw.name || raw.originalName) : (raw.title || raw.originalTitle), 200),
    year: yearOf(date),
    overview: Values.str(raw.overview, MAX_OVERVIEW),
    posterPath: safeImagePath(raw.posterPath),
    runtime: isTv ? 0 : Math.max(0, Values.int(raw.runtime, 0)),
    genres: genres,
    seasons: seasons,
    seasonCount: isTv ? Math.max(0, Values.int(raw.numberOfSeasons, seasons.length)) : 0,
    anime: anime,
    vote: typeof raw.voteAverage === "number" && isFinite(raw.voteAverage) ? Math.round(raw.voteAverage * 10) / 10 : 0
  }
}

function mediaKey(type, tmdbId) {
  return (type === "tv" ? "tv:" : "movie:") + Values.positiveId(tmdbId)
}

// ------------------------------------------------------------------ Radarr/Sonarr servers

function normalizeServers(value) {
  var out = []
  if (!Array.isArray(value)) return out
  for (var i = 0; i < value.length && out.length < 20; i++) {
    var s = value[i]
    if (!s || typeof s !== "object") continue
    var id = Values.int(s.id, -1)
    if (id < 0) continue
    out.push({
      id: id,
      name: Values.str(s.name, 80) || ("#" + id),
      is4k: Values.bool(s.is4k),
      isDefault: Values.bool(s.isDefault),
      activeProfileId: Values.int(s.activeProfileId, -1),
      activeDirectory: Values.str(s.activeDirectory, 1024),
      activeLanguageProfileId: Values.int(s.activeLanguageProfileId, -1),
      activeAnimeProfileId: Values.int(s.activeAnimeProfileId, -1),
      activeAnimeDirectory: Values.str(s.activeAnimeDirectory, 1024),
      activeAnimeLanguageProfileId: Values.int(s.activeAnimeLanguageProfileId, -1),
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
    var n = Values.int(value[i], -1)
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
    var id = Values.int(v.id, -1)
    if (id < 0) continue
    out.push({ id: id, name: Values.str(v[labelKey || "name"], 200) || ("#" + id) })
  }
  return out
}

function normalizeServerDetails(value) {
  var v = value && typeof value === "object" ? value : {}
  var folders = []
  if (Array.isArray(v.rootFolders)) {
    for (var i = 0; i < v.rootFolders.length && folders.length < 50; i++) {
      var f = v.rootFolders[i]
      var path = f && typeof f === "object" ? Values.str(f.path, 1024) : ""
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
