#!/usr/bin/env node
// A small stand-in for the Seerr API, faithful to the shapes the real server
// returns (seerr-api.yml and server/routes/*.ts), for developing the plugin
// without a Seerr instance.
//
//   node dev/mock-seerr.js [--port 5055] [--key devkey123456]
//
// Extra endpoints to drive it while testing:
//   POST /__mock/new?type=movie|tv[&tmdb=ID][&user=N][&4k=1]
//                                      add a pending request (triggers a notification)
//   POST /__mock/available?id=N        mark a request's media available
//   POST /__mock/fail?id=N             mark a request failed
//   POST /__mock/latency?ms=N          delay every API answer
//   POST /__mock/break?status=N        answer every API call with that status (0 = stop)

const http = require("http")
const { URL } = require("url")

const args = process.argv.slice(2)
const opt = (name, fallback) => {
  const at = args.indexOf("--" + name)
  return at !== -1 && args[at + 1] ? args[at + 1] : fallback
}
const PORT = Number(opt("port", 5055))
const KEY = opt("key", "devkey1234567890")

let latency = 0
let broken = 0

const users = {
  1: { id: 1, displayName: "Admin", email: "admin@example.com", permissions: 2, userType: 3 },
  3: { id: 3, displayName: "Alice", email: "alice@example.com", permissions: 32, userType: 3 },
  4: { id: 4, displayName: "Bob <b>bold</b>", email: "bob@example.com", permissions: 32, userType: 3 },
  5: { id: 5, displayName: "Carol", email: "carol@example.com", permissions: 32, userType: 3 }
}

const catalog = {
  "movie:693134": { title: "Dune: Part Two", releaseDate: "2024-02-27", runtime: 167, posterPath: "/1pdfLvkbY9ohJlCjQH2CZjjYVvJ.jpg", voteAverage: 8.2,
    genres: [{ id: 878, name: "Science Fiction" }, { id: 12, name: "Adventure" }],
    overview: "Follow the mythic journey of Paul Atreides as he unites with Chani and the Fremen while on a path of revenge against the conspirators who destroyed his family." },
  "movie:27205": { title: "Inception", releaseDate: "2010-07-15", runtime: 148, posterPath: "/9gk7adHYeDvHkCSEqAvQNLV5Uge.jpg", voteAverage: 8.4,
    genres: [{ id: 28, name: "Action" }, { id: 878, name: "Science Fiction" }],
    overview: "Cobb, a skilled thief who commits corporate espionage by infiltrating the subconscious of his targets, is offered a chance to regain his old life." },
  "movie:603": { title: "The Matrix", releaseDate: "1999-03-30", runtime: 136, posterPath: "/f89U3ADr1oiB1s9GkdPOEpXUk5H.jpg", voteAverage: 8.2,
    genres: [{ id: 28, name: "Action" }], overview: "Set in the 22nd century, The Matrix tells the story of a computer hacker who joins a group of underground insurgents." },
  "movie:550": { title: "<img src=\"https://example.invalid/tracker\"> Fight Club", releaseDate: "1999-10-15", runtime: 139, posterPath: "../../../etc/passwd",
    genres: [{ id: 18, name: "Drama" }], overview: "Markup-shaped title, to check it renders as plain text." },
  "tv:1399": { name: "Game of Thrones", firstAirDate: "2011-04-17", numberOfSeasons: 8, posterPath: "/1XS1oqL89opfnbLl8WnZY1O1uJx.jpg", voteAverage: 8.5,
    genres: [{ id: 10765, name: "Sci-Fi & Fantasy" }, { id: 18, name: "Drama" }],
    seasons: Array.from({ length: 9 }, (_, i) => ({ seasonNumber: i, name: i ? "Season " + i : "Specials", episodeCount: i ? 10 : 15 })),
    overview: "Seven noble families fight for control of the mythical land of Westeros." },
  "tv:1396": { name: "Breaking Bad", firstAirDate: "2008-01-20", numberOfSeasons: 5, posterPath: "/ggFHVNu6YYI5L9pCfOacjizRGt.jpg", voteAverage: 8.9,
    genres: [{ id: 18, name: "Drama" }, { id: 80, name: "Crime" }],
    seasons: Array.from({ length: 5 }, (_, i) => ({ seasonNumber: i + 1, name: "Season " + (i + 1), episodeCount: 13 })),
    overview: "Walter White, a New Mexico chemistry teacher, is diagnosed with Stage III cancer." },
  "tv:37854": { name: "One Piece", firstAirDate: "1999-10-20", numberOfSeasons: 2, posterPath: "/cMD9Ygz11zjJzAovURpO75Qg7rT.jpg", voteAverage: 8.7,
    keywords: [{ id: 210024, name: "anime" }], genres: [{ id: 16, name: "Animation" }],
    seasons: [{ seasonNumber: 1, name: "East Blue", episodeCount: 61 }, { seasonNumber: 2, name: "Alabasta", episodeCount: 77 }],
    overview: "Monkey D. Luffy sets off on an adventure with his pirate crew." }
}
const pool = [["movie", 693134], ["movie", 27205], ["movie", 603], ["movie", 550], ["tv", 1399], ["tv", 1396], ["tv", 37854]]

const radarr = [
  { id: 0, name: "Radarr", is4k: false, isDefault: true, activeDirectory: "/movies", activeProfileId: 4, activeTags: [1] },
  { id: 1, name: "Radarr 4K", is4k: true, isDefault: true, activeDirectory: "/movies4k", activeProfileId: 5, activeTags: [] }
]
const sonarr = [
  { id: 0, name: "Sonarr", is4k: false, isDefault: true, activeDirectory: "/tv", activeProfileId: 4, activeLanguageProfileId: 1,
    activeAnimeProfileId: 6, activeAnimeDirectory: "/anime", activeAnimeLanguageProfileId: 2, activeTags: [] }
]
const serviceDetails = {
  radarr: {
    profiles: [{ id: 4, name: "HD-1080p" }, { id: 5, name: "Ultra-HD" }, { id: 6, name: "Any" }],
    rootFolders: [{ id: 1, path: "/movies", freeSpace: 2.1e12, totalSpace: 8e12 }, { id: 2, path: "/movies4k", freeSpace: 9e11, totalSpace: 4e12 }],
    tags: [{ id: 1, label: "family" }, { id: 2, label: "kids" }]
  },
  sonarr: {
    profiles: [{ id: 4, name: "HD-1080p" }, { id: 6, name: "Anime" }],
    rootFolders: [{ id: 1, path: "/tv", freeSpace: 3.3e12 }, { id: 2, path: "/anime", freeSpace: 5e11 }],
    languageProfiles: [{ id: 1, name: "English" }, { id: 2, name: "Japanese" }],
    tags: [{ id: 3, label: "anime" }]
  }
}

let nextId = 1
const requests = []
const media = {}

function mediaFor(type, tmdbId) {
  const key = type + ":" + tmdbId
  if (!media[key]) media[key] = { id: Object.keys(media).length + 1, mediaType: type, tmdbId, tvdbId: type === "tv" ? tmdbId * 10 : null, status: 2, status4k: 1 }
  return media[key]
}

function addRequest(type, tmdbId, userId, opts = {}) {
  const now = new Date(Date.now() - (opts.ageMin || 0) * 60000).toISOString()
  const m = mediaFor(type, tmdbId)
  const req = {
    id: nextId++, status: opts.status || 1, createdAt: now, updatedAt: now, type, is4k: !!opts.is4k,
    serverId: null, profileId: null, rootFolder: null, languageProfileId: null, tags: null, isAutoRequest: false,
    media: m, seasons: type === "tv" ? (opts.seasons || [1]).map((n, i) => ({ id: i + 1, seasonNumber: n, status: 2 })) : [],
    modifiedBy: opts.status && opts.status !== 1 ? users[1] : null, requestedBy: users[userId]
  }
  if (req.status === 2 || req.status === 5) m.status = opts.available ? 5 : 3
  requests.push(req)
  return req
}

addRequest("movie", 693134, 3, { ageMin: 5 })
addRequest("tv", 1399, 4, { ageMin: 90, seasons: [6, 7, 8], is4k: false })
addRequest("tv", 37854, 5, { ageMin: 60 * 26, seasons: [1, 2] })
addRequest("movie", 550, 4, { ageMin: 60 * 50 })
addRequest("movie", 27205, 3, { ageMin: 60 * 24 * 5, status: 2, available: true })
addRequest("movie", 603, 5, { ageMin: 60 * 24 * 40, status: 3 })
addRequest("tv", 1396, 3, { ageMin: 60 * 24 * 3, status: 2, seasons: [1, 2, 3, 4, 5] })
// New requests get ids a restarted mock has never handed out, as a real Seerr
// never reuses one; otherwise the plugin would take them for already seen.
nextId = Math.max(nextId, Math.floor(Date.now() / 1000) % 1000000)

function send(res, status, body) {
  const text = body === undefined ? "" : JSON.stringify(body)
  setTimeout(() => {
    res.writeHead(status, { "Content-Type": "application/json" })
    res.end(text)
  }, latency)
}

function readBody(req) {
  return new Promise(resolve => {
    let data = ""
    req.on("data", c => { data += c; if (data.length > 1e6) req.destroy() })
    req.on("end", () => { try { resolve(data ? JSON.parse(data) : {}) } catch (e) { resolve(null) } })
  })
}

function statusFilter(filter) {
  switch (filter) {
    case "approved": case "processing": return [2]
    case "pending": return [1]
    case "unavailable": return [1, 2]
    case "failed": return [4]
    case "completed": case "available": case "deleted": return [5, 2]
    default: return [1, 2, 3, 4, 5]
  }
}

function mediaFilter(filter) {
  switch (filter) {
    case "available": return [5]
    case "processing": case "unavailable": return [1, 2, 3, 4]
    case "deleted": return [7]
    default: return [1, 2, 3, 4, 5, 7]
  }
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, "http://localhost")
  const path = url.pathname
  const q = url.searchParams
  console.log(new Date().toISOString().slice(11, 19), req.method, req.url)

  if (path.startsWith("/__mock/")) {
    if (path === "/__mock/new") {
      const type = q.get("type") || (Math.random() < 0.5 ? "movie" : "tv")
      const choices = pool.filter(p => p[0] === type)
      const forced = pool.find(p => String(p[1]) === q.get("tmdb"))
      const [t, id] = forced || choices[Math.floor(Math.random() * choices.length)]
      const user = q.get("user") ? Number(q.get("user")) : [3, 4, 5][Math.floor(Math.random() * 3)]
      const r = addRequest(t, id, users[user] ? user : 3, { seasons: t === "tv" ? [1] : undefined, is4k: q.get("4k") === "1" })
      return send(res, 201, r)
    }
    const r = requests.find(x => x.id === Number(q.get("id")))
    if (path === "/__mock/available" && r) { r.status = 2; r.media.status = 5; r.updatedAt = new Date().toISOString(); return send(res, 200, r) }
    if (path === "/__mock/fail" && r) { r.status = 4; r.updatedAt = new Date().toISOString(); return send(res, 200, r) }
    if (path === "/__mock/latency") { latency = Number(q.get("ms") || 0); return send(res, 200, { latency }) }
    if (path === "/__mock/break") { broken = Number(q.get("status") || 0); return send(res, 200, { broken }) }
    return send(res, 404, { message: "unknown mock control" })
  }

  if (!path.startsWith("/api/v1/")) return send(res, 404, { message: "Not Found" })
  if (req.headers["x-api-key"] !== KEY) return send(res, 403, { message: "You do not have permission to access this endpoint" })
  if (broken) return send(res, broken, { message: "Mock is broken on purpose (" + broken + ")" })
  const api = path.slice("/api/v1".length)
  let m

  if (req.method === "GET" && api === "/status") return send(res, 200, { version: "3.0.0-mock", commitTag: "mock" })
  if (req.method === "GET" && api === "/auth/me") return send(res, 200, users[1])

  if (req.method === "GET" && api === "/request/count") {
    const c = { total: requests.length, movie: 0, tv: 0, pending: 0, approved: 0, declined: 0, processing: 0, available: 0, completed: 0 }
    for (const r of requests) {
      c[r.type]++
      if (r.status === 1) c.pending++
      if (r.status === 2) { c.approved++; if (r.media.status === 5) c.available++; else c.processing++ }
      if (r.status === 3) c.declined++
      if (r.status === 5) c.completed++
    }
    return send(res, 200, c)
  }

  if (req.method === "GET" && api === "/request") {
    const take = Number(q.get("take") || 10), skip = Number(q.get("skip") || 0)
    const sf = statusFilter(q.get("filter")), mf = mediaFilter(q.get("filter"))
    const type = q.get("mediaType") || "all"
    const by = q.get("requestedBy") ? Number(q.get("requestedBy")) : null
    const field = q.get("sort") === "modified" ? "updatedAt" : "createdAt"
    const dir = q.get("sortDirection") === "asc" ? 1 : -1
    let list = requests.filter(r => sf.includes(r.status) && mf.includes(r.media.status) && (type === "all" || r.type === type) && (!by || r.requestedBy.id === by))
    list.sort((a, b) => dir * (Date.parse(a[field]) - Date.parse(b[field])))
    return send(res, 200, { pageInfo: { pages: Math.ceil(list.length / take), pageSize: take, results: list.length, page: Math.floor(skip / take) + 1 }, results: list.slice(skip, skip + take) })
  }

  if ((m = api.match(/^\/request\/(\d+)$/))) {
    const r = requests.find(x => x.id === Number(m[1]))
    if (!r) return send(res, 404, { message: "Request not found." })
    if (req.method === "GET") return send(res, 200, r)
    if (req.method === "DELETE") { requests.splice(requests.indexOf(r), 1); return send(res, 204) }
    if (req.method === "PUT") {
      if (r.status !== 1) return send(res, 409, { message: "Only pending requests can be modified." })
      const body = await readBody(req)
      if (!body) return send(res, 400, { message: "Bad JSON" })
      if (r.type === "tv" && (!Array.isArray(body.seasons) || body.seasons.length === 0))
        return send(res, 400, { message: "Missing seasons. If you want to cancel a series request, use the DELETE method." })
      r.serverId = body.serverId; r.profileId = body.profileId; r.rootFolder = body.rootFolder; r.tags = body.tags
      if (r.type === "tv") { r.languageProfileId = body.languageProfileId; r.seasons = body.seasons.map((n, i) => ({ id: i + 1, seasonNumber: n, status: 2 })) }
      r.updatedAt = new Date().toISOString()
      console.log("  updated:", JSON.stringify(body))
      return send(res, 200, r)
    }
  }

  if (req.method === "POST" && (m = api.match(/^\/request\/(\d+)\/(approve|decline|retry)$/))) {
    const r = requests.find(x => x.id === Number(m[1]))
    if (!r) return send(res, 404, { message: "Request not found." })
    if (m[2] === "retry") {
      if (r.status !== 4) return send(res, 409, { message: "Only failed requests can be retried." })
      r.status = 2
    } else {
      if (r.status !== 1) return send(res, 409, { message: "Only pending requests can be approved or declined." })
      r.status = m[2] === "approve" ? 2 : 3
      if (r.status === 2) r.media.status = 3
    }
    r.modifiedBy = users[1]
    r.updatedAt = new Date().toISOString()
    return send(res, 200, r)
  }

  if (req.method === "GET" && (m = api.match(/^\/(movie|tv)\/(\d+)$/))) {
    const d = catalog[m[1] + ":" + m[2]]
    if (!d) return send(res, 404, { message: "Unable to retrieve media." })
    return send(res, 200, Object.assign({ id: Number(m[2]) }, d))
  }

  if (req.method === "GET" && (m = api.match(/^\/service\/(radarr|sonarr)$/))) return send(res, 200, m[1] === "radarr" ? radarr : sonarr)
  if (req.method === "GET" && (m = api.match(/^\/service\/(radarr|sonarr)\/(\d+)$/))) {
    const list = m[1] === "radarr" ? radarr : sonarr
    const s = list.find(x => x.id === Number(m[2]))
    if (!s) return send(res, 404, { message: "Server does not exist." })
    return send(res, 200, Object.assign({ server: s }, serviceDetails[m[1]], { languageProfiles: serviceDetails[m[1]].languageProfiles || null }))
  }

  send(res, 404, { message: "Not Found" })
})

server.listen(PORT, "127.0.0.1", () => console.log(`mock Seerr on http://127.0.0.1:${PORT}  (API key: ${KEY})`))
