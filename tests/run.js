#!/usr/bin/env node
// Unit tests for model/Seerr.js. Run: node tests/run.js

const { load, fixture, test, eq, report } = require("./harness")
const S = load("model/Seerr.js")

// ------------------------------------------------------------------ URLs

test("normalizeBaseUrl accepts https and http", () => {
  eq(S.normalizeBaseUrl("https://seerr.example.com/").url, "https://seerr.example.com")
  eq(S.normalizeBaseUrl("http://192.168.1.10:5055").url, "http://192.168.1.10:5055")
  eq(S.normalizeBaseUrl("http://192.168.1.10:5055").secure, false)
  eq(S.normalizeBaseUrl("https://x.example.com").secure, true)
})

test("normalizeBaseUrl defaults to https and strips /api/v1", () => {
  eq(S.normalizeBaseUrl("seerr.lan").url, "https://seerr.lan")
  eq(S.normalizeBaseUrl("https://host.example/seerr/api/v1/").url, "https://host.example/seerr")
  eq(S.normalizeBaseUrl("HTTPS://Host.Example:443").url, "https://host.example:443")
  eq(S.normalizeBaseUrl("http://[::1]:5055").url, "http://[::1]:5055")
  eq(S.normalizeBaseUrl("localhost:5055").url, "https://localhost:5055")
})

test("normalizeBaseUrl refuses other schemes and junk", () => {
  eq(S.normalizeBaseUrl("ftp://host").ok, false)
  eq(S.normalizeBaseUrl("javascript:alert(1)").ok, false)
  eq(S.normalizeBaseUrl("https://user:pass@host").ok, false)
  eq(S.normalizeBaseUrl("https://host/?q=1").ok, false)
  eq(S.normalizeBaseUrl("https://host:99999").ok, false)
  eq(S.normalizeBaseUrl("https://ho st").ok, false)
  eq(S.normalizeBaseUrl("https://host/<script>").ok, false)
  eq(S.normalizeBaseUrl("").error, "empty")
  eq(S.normalizeBaseUrl(null).ok, false)
})

test("isPrivateHost", () => {
  for (const u of ["http://localhost:5055", "http://127.0.0.1", "http://192.168.1.2:5055", "http://10.0.0.3", "http://172.20.1.1",
    "http://seerr.lan", "http://nas.local", "http://seerr", "http://[::1]:5055", "http://100.101.102.103"]) eq([u, S.isPrivateHost(u)], [u, true])
  for (const u of ["http://seerr.example.com", "http://8.8.8.8", "http://172.32.0.1", "http://[2001:db8::1]"]) eq([u, S.isPrivateHost(u)], [u, false])
})

test("parseSettingValue", () => {
  eq(S.parseSettingValue("notifyPoster", "off"), false)
  eq(S.parseSettingValue("notifyPoster", "maybe"), undefined)
  eq(S.parseSettingValue("pageSize", "30"), 30)
  eq(S.parseSettingValue("pageSize", "-3"), undefined)
  eq(S.parseSettingValue("defaultFilter", "declined"), "declined")
  eq(S.parseSettingValue("defaultFilter", "bogus"), undefined)
  eq(S.parseSettingValue("url", "seerr.lan:5055/"), "https://seerr.lan:5055")
  eq(S.parseSettingValue("url", "ftp://x"), undefined)
  eq(S.parseSettingValue("nope", "1"), undefined)
  eq(S.parseSettingValue("__proto__", "1"), undefined)
})

test("listPath maps filters and clamps", () => {
  eq(S.listPath({ filter: "pending", take: 20, skip: 0, sort: "added", sortDirection: "desc", mediaType: "all" }),
    "/request?take=20&skip=0&filter=pending&sort=added&sortDirection=desc&mediaType=all")
  eq(S.listPath({ filter: "declined", take: 500, skip: -3, sort: "bogus", sortDirection: "asc", mediaType: "tv", requestedBy: 4 }),
    "/request?take=100&skip=0&filter=all&sort=added&sortDirection=asc&mediaType=tv&requestedBy=4")
})

test("poster paths are validated", () => {
  eq(S.posterUrl("/abc_DEF-1.jpg", "w92"), "https://image.tmdb.org/t/p/w92/abc_DEF-1.jpg")
  eq(S.posterUrl("https://evil.example/x.jpg"), "")
  eq(S.posterUrl("/../../etc/passwd"), "")
  eq(S.posterUrl("/x.jpg?track=1"), "")
  eq(S.posterUrl(null), "")
})

test("webUrl points at the media page", () => {
  eq(S.webUrl("https://s.example", "tv", 1399), "https://s.example/tv/1399")
  eq(S.webUrl("https://s.example", "movie", 0), "https://s.example")
})

// ------------------------------------------------------------------ payloads

const list = S.normalizeRequestList(JSON.parse(fixture("requests.json")))

test("normalizeRequestList drops invalid rows", () => {
  eq(list.requests.map(r => r.id), [12, 11, 10, 9])
  eq(list.total, 4)
})

test("normalizeRequest reads movie fields", () => {
  const r = list.requests[0]
  eq(r.type, "movie")
  eq(r.tmdbId, 438631)
  eq(r.serverId, -1)
  eq(r.requestedBy, { id: 3, name: "Alice" })
  eq(r.createdAt, Date.parse("2026-11-08T10:00:00.000Z"))
  eq(r.tags, [])
})

test("normalizeRequest reads tv fields, sorts seasons, uses 4K status", () => {
  const r = list.requests[1]
  eq(r.type, "tv")
  eq(r.seasons, [1, 2, 3])
  eq(r.is4k, true)
  eq(r.mediaStatus, 2)
  eq(r.tags, [2])
  eq(r.rootFolder, "/tv4k")
  // Markup-shaped names stay plain strings; escaping is the sink's job.
  eq(r.requestedBy.name, "<b>Bob</b>")
})

test("normalizeUser falls back through name fields", () => {
  eq(list.requests[3].requestedBy, { id: 5, name: "carol" })
  eq(S.normalizeUser({ id: 9 }), { id: 9, name: "#9" })
  eq(S.normalizeUser({ id: -1 }), null)
})

test("strings are bounded and stripped of controls", () => {
  const long = "a".repeat(5000)
  eq(S.str(long, 10).length, 10)
  eq(S.str("a\u0000b\u001bc"), "abc")
  eq(S.str({ toString() { return "x" } }), "")
})

test("parseJson refuses huge or broken bodies", () => {
  eq(S.parseJson("{").ok, false)
  eq(S.parseJson("x".repeat(S.MAX_RESPONSE + 1)).error, "tooLarge")
  eq(S.parseJson("").value, null)
})

test("normalizeMedia movie and tv", () => {
  const movie = S.normalizeMedia({ title: "Dune: Part Two", releaseDate: "2024-02-27", overview: "x", posterPath: "/p.jpg", runtime: 166, genres: [{ name: "SF" }], voteAverage: 8.234 }, "movie")
  eq(movie.title, "Dune: Part Two")
  eq(movie.year, "2024")
  eq(movie.runtime, 166)
  eq(movie.vote, 8.2)
  const tv = S.normalizeMedia({ name: "Show", firstAirDate: "2011-04-17", numberOfSeasons: 2, posterPath: "bad", keywords: [{ id: 210024 }],
    seasons: [{ seasonNumber: 1, name: "S1", episodeCount: 10 }, { seasonNumber: 0, name: "Specials", episodeCount: 3 }] }, "tv")
  eq(tv.seasons.map(s => s.seasonNumber), [0, 1])
  eq(tv.posterPath, "")
  eq(tv.anime, true)
  eq(tv.year, "2011")
})

test("normalizeCounts", () => {
  eq(S.normalizeCounts({ pending: 3, total: "x" }).pending, 3)
  eq(S.normalizeCounts(null).pending, 0)
})

// ------------------------------------------------------------------ statuses

test("statusKey combines request and media status", () => {
  const k = (status, mediaStatus) => S.statusKey({ status, mediaStatus })
  eq(k(1, 1), "pending")
  eq(k(2, 3), "processing")
  eq(k(2, 4), "partial")
  eq(k(2, 5), "available")
  eq(k(3, 1), "declined")
  eq(k(4, 1), "failed")
  eq(k(5, 5), "available")
  eq(k(5, 7), "deleted")
  eq(k(9, 1), "unknown")
})

test("statusColor follows Seerr and keeps pending neutral", () => {
  eq(S.statusColor("pending"), "")
  eq(S.statusColor("available"), "#22c55e")
  eq(S.statusColor("processing"), "#6366f1")
  eq(S.statusColor("declined"), "#dc2626")
  eq(S.statusColor("failed"), "#dc2626")
  eq(S.statusColor("nope"), "dim")
})

// ------------------------------------------------------------------ list view

test("matchesView: declined client filter and search", () => {
  const media = { title: "Inception", year: "2010" }
  eq(S.matchesView(list.requests[3], { filter: "declined" }, null), true)
  eq(S.matchesView(list.requests[2], { filter: "declined" }, null), false)
  eq(S.matchesView(list.requests[2], { filter: "all", search: "incep 2010" }, media), true)
  eq(S.matchesView(list.requests[2], { filter: "all", search: "alice" }, media), true)
  eq(S.matchesView(list.requests[2], { filter: "all", search: "matrix" }, media), false)
})

test("mergePage keeps order and drops duplicates", () => {
  eq(S.mergePage([{ id: 1 }, { id: 2 }], [{ id: 2 }, { id: 3 }]).map(r => r.id), [1, 2, 3])
  eq(S.removeRequest([{ id: 1 }, { id: 2 }], 1).map(r => r.id), [2])
  eq(S.replaceRequest([{ id: 1, a: 1 }], { id: 1, a: 2 }), [{ id: 1, a: 2 }])
})

// ------------------------------------------------------------------ settings

test("normalizeSettings clamps and defaults", () => {
  const s = S.normalizeSettings({ url: "seerr.lan/", refreshIntervalSec: 2, defaultFilter: "nope", pageSize: "50", notifyNewRequests: false, extra: 1 })
  eq(s.url, "https://seerr.lan")
  eq(s.refreshIntervalSec, 15)
  eq(s.defaultFilter, "pending")
  eq(s.pageSize, 50)
  eq(s.notifyNewRequests, false)
  eq(s.showPosters, true)
  eq("extra" in s, false)
  eq(S.normalizeSettings(null).url, "")
  eq(S.normalizeSettings({ url: "ftp://x" }).url, "")
})

test("findBarEntry searches every section", () => {
  const cfg = { layout: { left: [{ id: "a" }], right: [{ id: "myouboku.omaseerr", url: "x" }] } }
  eq(S.findBarEntry(cfg, "myouboku.omaseerr"), { id: "myouboku.omaseerr", url: "x" })
  eq(S.findBarEntry({ layout: { tray: ["myouboku.omaseerr"] } }, "myouboku.omaseerr"), { id: "myouboku.omaseerr" })
  eq(S.findBarEntry({}, "x"), null)
})

// ------------------------------------------------------------------ notifications

test("newRequestIds and rememberIds", () => {
  eq(S.newRequestIds([11, 10], list.requests.slice(0, 2)), [12])
  eq(S.rememberIds([1, 2], [3, 2]), [3, 2, 1])
  const many = Array.from({ length: 1500 }, (_, i) => i + 1)
  eq(S.rememberIds([], many).length, S.MAX_SEEN)
})

test("statusChanges reports available and failed transitions only", () => {
  const prev = { 10: "processing", 9: "pending", 12: "pending" }
  const changes = S.statusChanges(prev, list.requests)
  eq(changes, [{ id: 10, from: "processing", to: "available" }])
  eq(S.statusMap(list.requests)[9], "declined")
})

test("neutralizeMarkup survives the daemon's entity decoding", () => {
  const out = S.neutralizeMarkup("<b>x</b> &lt;i&gt; &amp;")
  // Mirror of the daemon: decode entities, escape, restore allowed tags.
  const decoded = out.replace(/&(lt|gt|amp);/g, (_, n) => ({ lt: "<", gt: ">", amp: "&" })[n])
  eq(/<b>|<i>|<\/b>/.test(decoded), false)
  eq(out.replace(/\u2060/g, ""), "<b>x</b> &lt;i&gt; &amp;")
})

test("parseState is defensive", () => {
  eq(S.parseState("garbage"), { url: "", seen: [], statuses: {}, primed: false })
  const st = S.parseState(JSON.stringify({ url: "https://a", seen: [3, "4", -1, 3], statuses: { "5": "pending", "x": "y", "6": 1 }, primed: true }))
  eq(st.seen, [3, 4])
  eq(st.statuses, { 5: "pending" })
  eq(st.primed, true)
})

// ------------------------------------------------------------------ approval

const servers = S.normalizeServers([
  { id: 0, name: "Sonarr", is4k: false, isDefault: true, activeProfileId: 4, activeDirectory: "/tv", activeLanguageProfileId: 1,
    activeAnimeProfileId: 5, activeAnimeDirectory: "/anime", activeAnimeLanguageProfileId: 2, activeTags: [1], activeAnimeTags: [3] },
  { id: 1, name: "Sonarr 4K", is4k: true, isDefault: true, activeProfileId: 6, activeDirectory: "/tv4k", activeTags: [] },
  { id: "bad" }
])
const details = S.normalizeServerDetails({
  profiles: [{ id: 4, name: "HD" }, { id: 5, name: "Anime" }, { id: 6, name: "UHD" }],
  rootFolders: [{ id: 1, path: "/tv", freeSpace: 1e12 }, { id: 2, path: "/anime" }, { id: 3, path: "/tv4k" }],
  languageProfiles: [{ id: 1, name: "English" }, { id: 2, name: "Japanese" }],
  tags: [{ id: 1, label: "family" }, { id: 3, label: "anime" }]
})

test("normalizeServers and details", () => {
  eq(servers.length, 2)
  eq(details.tags, [{ id: 1, name: "family" }, { id: 3, name: "anime" }])
  eq(details.rootFolders[1].freeSpace, -1)
  eq(S.normalizeServerDetails({ profiles: [] }).languageProfiles, null)
})

test("pickServer honours request, then default for 4K-ness", () => {
  const hd = { is4k: false, serverId: -1 }
  eq(S.pickServer(servers, hd).id, 0)
  eq(S.pickServer(servers, { is4k: true, serverId: -1 }).id, 1)
  eq(S.pickServer(servers, { is4k: false, serverId: 1 }).id, 1)
  eq(S.pickServer([], hd), null)
})

test("defaultForm uses request values, then (anime) server defaults", () => {
  const req = list.requests[1] // tv 4K, server 1, profile 6
  const form = S.defaultForm(req, servers[1], details, false)
  eq(form.profileId, 6)
  eq(form.rootFolder, "/tv4k")
  eq(form.seasons, [1, 2, 3])
  const plain = Object.assign({}, req, { serverId: -1, profileId: -1, rootFolder: "", languageProfileId: -1, tags: [] })
  const anime = S.defaultForm(plain, servers[0], details, true)
  eq([anime.profileId, anime.rootFolder, anime.languageProfileId, anime.tags], [5, "/anime", 2, [3]])
  const normal = S.defaultForm(plain, servers[0], details, false)
  eq([normal.profileId, normal.rootFolder, normal.languageProfileId, normal.tags], [4, "/tv", 1, [1]])
})

test("defaultForm falls back when defaults are unknown to the server", () => {
  const req = Object.assign({}, list.requests[0])
  const odd = Object.assign({}, servers[0], { activeProfileId: 99, activeDirectory: "/gone", activeTags: [42] })
  const form = S.defaultForm(req, odd, details, false)
  eq([form.profileId, form.rootFolder, form.tags], [4, "/tv", []])
  eq(S.defaultForm(req, null, null, false).serverId, -1)
})

test("formProblem and updateBody", () => {
  const tv = list.requests[1]
  const form = { serverId: 1, profileId: 6, rootFolder: "/tv4k", languageProfileId: 1, tags: [1], seasons: [3, 1] }
  eq(S.formProblem(tv, form), "")
  eq(S.formProblem(tv, Object.assign({}, form, { seasons: [] })), "noSeasons")
  eq(S.formProblem(tv, Object.assign({}, form, { rootFolder: "" })), "noRootFolder")
  eq(S.formProblem(tv, null), "noServer")
  eq(S.updateBody(tv, form), { mediaType: "tv", serverId: 1, profileId: 6, rootFolder: "/tv4k", tags: [1], seasons: [1, 3], languageProfileId: 1 })
  eq(S.updateBody(list.requests[0], form), { mediaType: "movie", serverId: 1, profileId: 6, rootFolder: "/tv4k", tags: [1] })
})

test("toggleInList", () => {
  eq(S.toggleInList([1, 3], 2), [1, 2, 3])
  eq(S.toggleInList([1, 3], 3), [1])
})

// ------------------------------------------------------------------ display

test("relativeTime", () => {
  const words = { now: "now", minutes: n => n + "m", hours: n => n + "h", days: n => n + "d", date: () => "date" }
  const now = Date.parse("2026-11-08T12:00:00Z")
  eq(S.relativeTime(now - 30e3, now, words), "now")
  eq(S.relativeTime(now - 5 * 60e3, now, words), "5m")
  eq(S.relativeTime(now - 3 * 3600e3, now, words), "3h")
  eq(S.relativeTime(now - 2 * 86400e3, now, words), "2d")
  eq(S.relativeTime(now - 90 * 86400e3, now, words), "date")
  eq(S.relativeTime(0, now, words), "")
})

test("seasonsLabel collapses runs", () => {
  eq(S.seasonsLabel([1, 2, 3, 5, 7, 8]), "1–3, 5, 7–8")
  eq(S.seasonsLabel([4]), "4")
  eq(S.seasonsLabel([]), "")
})

test("formatBytes", () => {
  eq(S.formatBytes(1536), "1.5 KB")
  eq(S.formatBytes(2 * 1024 ** 4), "2.0 TB")
  eq(S.formatBytes(-1), "")
})

report()
