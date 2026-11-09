// Tests for model/details.js.

const { load, test, eq } = require("./harness")
const Requests = load("model/requests.js")
const Details = load("model/details.js")

const now = Date.parse("2026-11-08T12:00:00Z")
const day = 86400e3

test("releaseState for a movie", () => {
  eq(Details.releaseState(null, false, now), { kind: "", date: 0 })
  eq(Details.releaseState({ released: now - day, productionStatus: "Released" }, false, now), { kind: "released", date: now - day })
  eq(Details.releaseState({ released: now + 30 * day, productionStatus: "Post Production" }, false, now), { kind: "upcoming", date: now + 30 * day })
  // No date yet but announced: upcoming.
  eq(Details.releaseState({ released: 0, productionStatus: "Planned" }, false, now), { kind: "upcoming", date: 0 })
  eq(Details.releaseState({ released: now - day, productionStatus: "Canceled" }, false, now).kind, "canceled")
  eq(Details.releaseState({ released: 0, productionStatus: "" }, false, now).kind, "")
})

test("releaseState for a series", () => {
  eq(Details.releaseState({ released: now - 900 * day, productionStatus: "Ended" }, true, now).kind, "ended")
  eq(Details.releaseState({ released: now - 900 * day, productionStatus: "Returning Series" }, true, now).kind, "returning")
  eq(Details.releaseState({ released: now - 900 * day, productionStatus: "Canceled" }, true, now).kind, "canceled")
  eq(Details.releaseState({ released: now + day, productionStatus: "In Production" }, true, now).kind, "upcoming")
  eq(Details.releaseState({ released: now - day, productionStatus: "" }, true, now).kind, "returning")
})

test("nextEpisode only when it is still ahead", () => {
  const media = n => ({ nextEpisode: n })
  eq(Details.nextEpisode(media({ season: 2, episode: 5, airDate: now + day }), now), { season: 2, episode: 5, airDate: now + day })
  eq(Details.nextEpisode(media({ season: 2, episode: 5, airDate: now - 3 * day }), now), null)
  eq(Details.nextEpisode(media({ season: 2, episode: 5, airDate: 0 }), now), null)
  eq(Details.nextEpisode(media(null), now), null)
})

test("downloadRows: the request's side, progress, cap", () => {
  const dl = (size, left) => ({ title: "t", size, sizeLeft: left, eta: now + 60e3, season: 0, episode: 0 })
  const media = { info: { downloads: [dl(100, 25), dl(0, 0), dl(10, 10)], downloads4k: [dl(50, 0)] } }
  const r = Details.downloadRows(media, false, 2)
  eq(r.rows.map(x => [x.progress, x.known]), [[0.75, true], [0, false]])
  eq(r.more, 1)
  eq(Details.downloadRows(media, true, 5).rows[0].progress, 1)
  eq(Details.downloadRows(null, false, 5), { rows: [], more: 0 })
})

test("downloadLabel names the episode once", () => {
  eq(Details.downloadLabel({ title: "Show.S05E01.1080p.mkv", season: 5, episode: 1 }), "Show.S05E01.1080p.mkv")
  eq(Details.downloadLabel({ title: "show s5e1 web", season: 5, episode: 1 }), "show s5e1 web")
  eq(Details.downloadLabel({ title: "Show.Complete.Pack", season: 5, episode: 1 }), "S05E01 · Show.Complete.Pack")
  // E1 is not E12.
  eq(Details.downloadLabel({ title: "Show.S05E12.mkv", season: 5, episode: 1 }), "S05E01 · Show.S05E12.mkv")
  eq(Details.downloadLabel({ title: "", season: 12, episode: 3 }), "S12E03")
  eq(Details.downloadLabel({ title: "Movie.2160p.mkv", season: 0, episode: 0 }), "Movie.2160p.mkv")
})

test("seasonStatusKey reads the request's side", () => {
  const media = { info: { seasons: [
    { seasonNumber: 1, status: Requests.MEDIA_AVAILABLE, status4k: Requests.MEDIA_UNKNOWN },
    { seasonNumber: 2, status: Requests.MEDIA_PROCESSING, status4k: Requests.MEDIA_PARTIALLY_AVAILABLE },
    { seasonNumber: 3, status: Requests.MEDIA_PENDING, status4k: 0 }] } }
  eq(Details.seasonStatusKey(media, false, 1), "available")
  eq(Details.seasonStatusKey(media, true, 1), "")
  eq(Details.seasonStatusKey(media, false, 2), "processing")
  eq(Details.seasonStatusKey(media, true, 2), "partial")
  eq(Details.seasonStatusKey(media, false, 3), "pending")
  eq(Details.seasonStatusKey(media, false, 9), "")
  eq(Details.seasonStatusKey(null, false, 1), "")
})

test("watchUrl and certification", () => {
  const media = { info: { mediaUrl: "https://a", mediaUrl4k: "" }, certifications: [{ country: "US", rating: "PG-13" }, { country: "FR", rating: "12" }] }
  eq(Details.watchUrl(media, false), "https://a")
  eq(Details.watchUrl(media, true), "")
  eq(Details.certification(media, ["FR", "US"]), "12")
  eq(Details.certification(media, ["DE", "US"]), "PG-13")
  eq(Details.certification(media, ["DE"]), "")
})

test("choices names the server, profiles and tags, skipping unknown ids", () => {
  const servers = [{ id: 0, name: "Radarr" }, { id: 1, name: "Radarr 4K" }]
  const details = { profiles: [{ id: 4, name: "HD-1080p" }], languageProfiles: [{ id: 2, name: "Japanese" }], tags: [{ id: 1, name: "family" }] }
  const req = { serverId: 1, profileId: 4, languageProfileId: 2, tags: [1, 9] }
  eq(Details.choices(req, servers, details), { server: "Radarr 4K", profile: "HD-1080p", language: "Japanese", tags: ["family"] })
  eq(Details.choices(Object.assign({}, req, { profileId: 99 }), servers, null), { server: "Radarr 4K", profile: "", language: "", tags: [] })
  eq(Details.choices(Object.assign({}, req, { serverId: -1 }), servers, details), { server: "", profile: "", language: "", tags: [] })
})
