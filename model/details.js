// What a request's details show beyond the request itself, from the media's
// details: whether it is out yet, the downloads under way, each season's
// status, the age rating to show, and the choices made when it was
// approved. The wording and locale formatting stay in QML.
.pragma library
.import "requests.js" as Requests

// Where a movie or series stands, for its release line:
//   { kind, date }  kind is "upcoming" (date ahead), "released", "canceled"
//   for a movie; "upcoming", "returning", "ended", "canceled" for a series;
//   "" when nothing is known. `date` is the release / first air date.
function releaseState(media, isTv, now) {
  if (!media) return { kind: "", date: 0 }
  var date = media.released || 0
  var st = media.productionStatus || ""
  if (st === "Canceled") return { kind: "canceled", date: date }
  if (date > now || (!date && /^(Planned|In Production|Post Production|Rumored|Pilot)$/.test(st)))
    return { kind: "upcoming", date: date }
  if (isTv) {
    if (st === "Ended") return { kind: "ended", date: date }
    if (st === "Returning Series" || st === "In Production") return { kind: "returning", date: date }
    return { kind: date ? "returning" : "", date: date }
  }
  return { kind: date ? "released" : "", date: date }
}

// The next episode worth announcing (one with an air date still ahead), or
// null.
function nextEpisode(media, now) {
  var n = media && media.nextEpisode
  if (!n || !n.airDate || n.airDate < now - 86400000) return null
  return n
}

// The downloads of the request's side (4K or not), as shown: at most
// `max`, each with its progress (0 to 1) and expected end, plus how many
// more there are.
function downloadRows(media, is4k, max) {
  var info = media && media.info
  var list = info ? (is4k ? info.downloads4k : info.downloads) : []
  var rows = []
  for (var i = 0; i < list.length && rows.length < max; i++) {
    var d = list[i]
    rows.push({
      title: d.title,
      progress: d.size > 0 ? Math.max(0, Math.min(1, (d.size - d.sizeLeft) / d.size)) : 0,
      known: d.size > 0,
      eta: d.eta,
      season: d.season,
      episode: d.episode
    })
  }
  return { rows: rows, more: Math.max(0, list.length - rows.length) }
}

// What a download row is called: its title, with the episode in front
// ("S02E05 · …") unless the title already names it, as release names do.
function downloadLabel(row) {
  if (!row.episode) return row.title
  var tag = "S" + (row.season < 10 ? "0" : "") + row.season + "E" + (row.episode < 10 ? "0" : "") + row.episode
  var named = new RegExp("S0*" + row.season + "[ ._-]?E0*" + row.episode + "(?!\\d)", "i").test(row.title)
  return named || !row.title ? (row.title || tag) : tag + " · " + row.title
}

// A season's status on the request's side, as a status key the panel has
// words and colours for ("" when Seerr knows nothing of it).
function seasonStatusKey(media, is4k, seasonNumber) {
  var seasons = media && media.info ? media.info.seasons : []
  for (var i = 0; i < seasons.length; i++) {
    if (seasons[i].seasonNumber !== seasonNumber) continue
    switch (is4k ? seasons[i].status4k : seasons[i].status) {
    case Requests.MEDIA_AVAILABLE: return "available"
    case Requests.MEDIA_PARTIALLY_AVAILABLE: return "partial"
    case Requests.MEDIA_PROCESSING: return "processing"
    case Requests.MEDIA_PENDING: return "pending"
    }
    return ""
  }
  return ""
}

// The media server's page for the request's side, or "".
function watchUrl(media, is4k) {
  var info = media && media.info
  return info ? (is4k ? info.mediaUrl4k : info.mediaUrl) : ""
}

// The age rating for the first of `countries` that has one ("FR", then
// "US"…), or "".
function certification(media, countries) {
  var list = media && media.certifications ? media.certifications : []
  for (var i = 0; i < countries.length; i++)
    for (var j = 0; j < list.length; j++)
      if (list[j].country === countries[i]) return list[j].rating
  return ""
}

// The choices behind an approved request, by name: server, quality and
// language profiles, tags. `servers` is the Radarr/Sonarr server list and
// `details` that server's details (profiles, language profiles, tags);
// unknown ids are left out rather than shown as numbers.
function choices(req, servers, details) {
  var out = { server: "", profile: "", language: "", tags: [] }
  if (!req || req.serverId < 0) return out
  for (var i = 0; i < (servers || []).length; i++)
    if (servers[i].id === req.serverId) out.server = servers[i].name
  if (!details) return out
  var find = function(list, id, field) {
    for (var k = 0; k < (list || []).length; k++) if (list[k].id === id) return list[k][field]
    return ""
  }
  out.profile = find(details.profiles, req.profileId, "name")
  out.language = find(details.languageProfiles, req.languageProfileId, "name")
  for (var t = 0; t < (req.tags || []).length; t++) {
    var label = find(details.tags, req.tags[t], "name")
    if (label) out.tags.push(label)
  }
  return out
}
