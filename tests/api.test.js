// Tests for model/api.js.

const { load, fixture, test, eq } = require("./harness")
const Api = load("model/api.js")

const list = Api.normalizeRequestList(JSON.parse(fixture("requests.json")))

const servers = Api.normalizeServers([
  { id: 0, name: "Sonarr", is4k: false, isDefault: true, activeProfileId: 4, activeDirectory: "/tv", activeLanguageProfileId: 1,
    activeAnimeProfileId: 5, activeAnimeDirectory: "/anime", activeAnimeLanguageProfileId: 2, activeTags: [1], activeAnimeTags: [3] },
  { id: 1, name: "Sonarr 4K", is4k: true, isDefault: true, activeProfileId: 6, activeDirectory: "/tv4k", activeTags: [] },
  { id: "bad" }
])

const details = Api.normalizeServerDetails({
  profiles: [{ id: 4, name: "HD" }, { id: 5, name: "Anime" }, { id: 6, name: "UHD" }],
  rootFolders: [{ id: 1, path: "/tv", freeSpace: 1e12 }, { id: 2, path: "/anime" }, { id: 3, path: "/tv4k" }],
  languageProfiles: [{ id: 1, name: "English" }, { id: 2, name: "Japanese" }],
  tags: [{ id: 1, label: "family" }, { id: 3, label: "anime" }]
})

test("normalizeBaseUrl accepts https and http", () => {
  eq(Api.normalizeBaseUrl("https://seerr.example.com/").url, "https://seerr.example.com")
  eq(Api.normalizeBaseUrl("http://192.168.1.10:5055").url, "http://192.168.1.10:5055")
  eq(Api.normalizeBaseUrl("http://192.168.1.10:5055").secure, false)
  eq(Api.normalizeBaseUrl("https://x.example.com").secure, true)
})

test("normalizeBaseUrl defaults to https and strips /api/v1", () => {
  eq(Api.normalizeBaseUrl("seerr.lan").url, "https://seerr.lan")
  eq(Api.normalizeBaseUrl("https://host.example/seerr/api/v1/").url, "https://host.example/seerr")
  eq(Api.normalizeBaseUrl("HTTPS://Host.Example:443").url, "https://host.example:443")
  eq(Api.normalizeBaseUrl("http://[::1]:5055").url, "http://[::1]:5055")
  eq(Api.normalizeBaseUrl("localhost:5055").url, "https://localhost:5055")
})

test("normalizeBaseUrl refuses other schemes and junk", () => {
  eq(Api.normalizeBaseUrl("ftp://host").ok, false)
  eq(Api.normalizeBaseUrl("javascript:alert(1)").ok, false)
  eq(Api.normalizeBaseUrl("https://user:pass@host").ok, false)
  eq(Api.normalizeBaseUrl("https://host/?q=1").ok, false)
  eq(Api.normalizeBaseUrl("https://host:99999").ok, false)
  eq(Api.normalizeBaseUrl("https://ho st").ok, false)
  eq(Api.normalizeBaseUrl("https://host/<script>").ok, false)
  eq(Api.normalizeBaseUrl("").error, "empty")
  eq(Api.normalizeBaseUrl(null).ok, false)
})

test("keyOrigin keeps scheme, host and port only", () => {
  eq(Api.keyOrigin("https://seerr.example.com/"), "https://seerr.example.com")
  eq(Api.keyOrigin("https://Host.Example/seerr/api/v1"), "https://host.example")
  eq(Api.keyOrigin("https://host.example:443/seerr"), "https://host.example")
  eq(Api.keyOrigin("http://host.example:80"), "http://host.example")
  eq(Api.keyOrigin("http://192.168.1.10:5055"), "http://192.168.1.10:5055")
  eq(Api.keyOrigin("https://host.example:80"), "https://host.example:80")
  eq(Api.keyOrigin("http://[::1]:5055"), "http://[::1]:5055")
  eq(Api.keyOrigin("seerr.lan"), "https://seerr.lan")
  // Same host, other scheme or port: another origin, so another key.
  eq(Api.keyOrigin("http://seerr.lan") === Api.keyOrigin("https://seerr.lan"), false)
  eq(Api.keyOrigin("https://seerr.lan:5055") === Api.keyOrigin("https://seerr.lan"), false)
  eq(Api.keyOrigin(""), "")
  eq(Api.keyOrigin("ftp://host"), "")
  eq(Api.keyOrigin("https://user:pass@host"), "")
})

test("isPrivateHost", () => {
  for (const u of ["http://localhost:5055", "http://127.0.0.1", "http://192.168.1.2:5055", "http://10.0.0.3", "http://172.20.1.1",
    "http://seerr.lan", "http://nas.local", "http://seerr", "http://[::1]:5055", "http://100.101.102.103"]) eq([u, Api.isPrivateHost(u)], [u, true])
  for (const u of ["http://seerr.example.com", "http://8.8.8.8", "http://172.32.0.1", "http://[2001:db8::1]"]) eq([u, Api.isPrivateHost(u)], [u, false])
})

test("listPath maps filters and clamps", () => {
  eq(Api.listPath({ filter: "pending", take: 20, skip: 0, sort: "added", sortDirection: "desc", mediaType: "all" }),
    "/request?take=20&skip=0&filter=pending&sort=added&sortDirection=desc&mediaType=all")
  eq(Api.listPath({ filter: "declined", take: 500, skip: -3, sort: "bogus", sortDirection: "asc", mediaType: "tv", requestedBy: 4 }),
    "/request?take=100&skip=0&filter=all&sort=added&sortDirection=asc&mediaType=tv&requestedBy=4")
})

test("poster paths are validated", () => {
  eq(Api.posterUrl("/abc_DEF-1.jpg", "w92"), "https://image.tmdb.org/t/p/w92/abc_DEF-1.jpg")
  eq(Api.posterUrl("https://evil.example/x.jpg"), "")
  eq(Api.posterUrl("/../../etc/passwd"), "")
  eq(Api.posterUrl("/x.jpg?track=1"), "")
  eq(Api.posterUrl(null), "")
})

test("actionTarget reads an id, with or without the server's origin", () => {
  eq(Api.actionTarget("42"), { id: 42, origin: "" })
  eq(Api.actionTarget(" 42@https://seerr.example.com "), { id: 42, origin: "https://seerr.example.com" })
  eq(Api.actionTarget("42abc").id, 0)
  eq(Api.actionTarget("-3").id, 0)
  eq(Api.actionTarget("@https://x").id, 0)
  eq(Api.actionTarget(null), { id: 0, origin: "" })
})

test("webUrl points at the media page", () => {
  eq(Api.webUrl("https://s.example", "tv", 1399), "https://s.example/tv/1399")
  eq(Api.webUrl("https://s.example", "movie", 0), "https://s.example")
})

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
  eq(Api.normalizeUser({ id: 9 }), { id: 9, name: "#9" })
  eq(Api.normalizeUser({ id: -1 }), null)
})

test("normalizeMedia movie and tv", () => {
  const movie = Api.normalizeMedia({ title: "Dune: Part Two", releaseDate: "2024-02-27", overview: "x", posterPath: "/p.jpg", runtime: 166, genres: [{ name: "SF" }], voteAverage: 8.234 }, "movie")
  eq(movie.title, "Dune: Part Two")
  eq(movie.year, "2024")
  eq(movie.runtime, 166)
  eq(movie.vote, 8.2)
  const tv = Api.normalizeMedia({ name: "Show", firstAirDate: "2011-04-17", numberOfSeasons: 2, posterPath: "bad", keywords: [{ id: 210024 }],
    seasons: [{ seasonNumber: 1, name: "S1", episodeCount: 10 }, { seasonNumber: 0, name: "Specials", episodeCount: 3 }] }, "tv")
  eq(tv.seasons.map(s => s.seasonNumber), [0, 1])
  eq(tv.posterPath, "")
  eq(tv.anime, true)
  eq(tv.year, "2011")
})

test("normalizeCounts", () => {
  eq(Api.normalizeCounts({ pending: 3, total: "x" }).pending, 3)
  eq(Api.normalizeCounts(null).pending, 0)
})

test("normalizeServers and details", () => {
  eq(servers.length, 2)
  eq(details.tags, [{ id: 1, name: "family" }, { id: 3, name: "anime" }])
  eq(details.rootFolders[1].freeSpace, -1)
  eq(Api.normalizeServerDetails({ profiles: [] }).languageProfiles, null)
})

test("normalizeMedia: release, people, ratings, trailer and Seerr's media info", () => {
  const movie = Api.normalizeMedia({
    title: "M", releaseDate: "2026-12-01", status: "Post Production", originalLanguage: "en",
    credits: { crew: [{ job: "Writer", name: "W" }, { job: "Director", name: "D1" }, { job: "Director", name: "D1" }, { job: "Director", name: "D2" }, { job: "Director", name: "D3" }] },
    releases: { results: [{ iso_3166_1: "FR", release_dates: [{ certification: "" }, { certification: "12" }] }, { iso_3166_1: "xx", release_dates: [{ certification: "X" }] }] },
    relatedVideos: [{ site: "YouTube", key: "teaser01", type: "Teaser" }, { site: "Vimeo", key: "vimeo001", type: "Trailer" }, { site: "YouTube", key: "trailer1", type: "Trailer" }],
    mediaInfo: {
      seasons: [], mediaUrl: "https://app.plex.tv/desktop#!/x", mediaUrl4k: "javascript:alert(1)",
      downloadStatus: [{ title: "M.2026.mkv", size: 1000, sizeLeft: 4000, estimatedCompletionTime: "2026-11-08T12:30:00Z", episode: { seasonNumber: 1, episodeNumber: 2 } }],
      downloadStatus4k: "nope"
    }
  }, "movie")
  eq(movie.released, Date.parse("2026-12-01"))
  eq(movie.productionStatus, "Post Production")
  eq(movie.people, ["D1", "D2"])
  eq(movie.networks, [])
  eq(movie.certifications, [{ country: "FR", rating: "12" }])
  eq(movie.originalLanguage, "en")
  eq(movie.trailer, "https://www.youtube.com/watch?v=trailer1")
  eq(movie.info.mediaUrl, "https://app.plex.tv/desktop#!/x")
  eq(movie.info.mediaUrl4k, "")
  eq(movie.info.downloads[0].sizeLeft, 1000) // never more than the size
  eq(movie.info.downloads[0].eta, Date.parse("2026-11-08T12:30:00Z"))
  eq([movie.info.downloads[0].season, movie.info.downloads[0].episode], [1, 2])
  eq(movie.info.downloads4k, [])
  eq(movie.nextEpisode, null)

  const tv = Api.normalizeMedia({
    name: "S", firstAirDate: "2011-04-17", status: "Returning Series", originalLanguage: "EN!",
    createdBy: [{ name: "C1" }, { name: "C2" }], networks: [{ name: "HBO" }, {}, "x"],
    contentRatings: { results: [{ iso_3166_1: "US", rating: "TV-MA" }, { iso_3166_1: "FR", rating: " " }] },
    nextEpisodeToAir: { seasonNumber: 2, episodeNumber: 5, airDate: "2026-11-14" },
    relatedVideos: [{ site: "YouTube", key: "bad key!", type: "Trailer" }],
    mediaInfo: { seasons: [{ seasonNumber: 1, status: 5, status4k: 1 }, { seasonNumber: -1 }] }
  }, "tv")
  eq(tv.people, ["C1", "C2"])
  eq(tv.networks, ["HBO"])
  eq(tv.certifications, [{ country: "US", rating: "TV-MA" }])
  eq(tv.originalLanguage, "")
  eq(tv.nextEpisode, { season: 2, episode: 5, airDate: Date.parse("2026-11-14") })
  eq(tv.trailer, "")
  eq(tv.info.seasons, [{ seasonNumber: 1, status: 5, status4k: 1 }])
  eq(tv.info.mediaUrl, "")
})

test("safeWebUrl keeps media-server links and drops the rest", () => {
  for (const ok of ["https://app.plex.tv/desktop#!/server/a/details?key=%2Flibrary%2Fmetadata%2F12",
                    "http://jelly.lan:8096/web/index.html#!/details?id=ab&context=home&serverId=x", "https://[::1]:8096/web"])
    eq(Api.safeWebUrl(ok), ok)
  for (const bad of ["javascript:alert(1)", "file:///etc/passwd", "https://user:pw@evil.com/", "https://a.com/\"x",
                     "https://evil.com\\@good.com/", "https://a.com/ x", "https://a.com/<b>", "ftp://a.com", "", 42, "https://" + "a".repeat(2050)])
    eq(Api.safeWebUrl(bad), "")
})
