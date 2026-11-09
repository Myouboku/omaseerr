// The approval form: which Radarr/Sonarr server it starts on and offers,
// its initial choices (as Seerr's own advanced requester makes them), what
// stops it from being sent, and the body it sends.
.pragma library

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

// The servers the approval form offers: those of the request's 4K-ness, plus
// the request's own server when it is of the other kind, since pickServer
// selects it and the form must be able to show what is selected.
function formServers(servers, req) {
  var out = servers.filter(function(s) { return s.is4k === !!req.is4k })
  var picked = pickServer(servers, req)
  if (picked && out.indexOf(picked) === -1) out.unshift(picked)
  return out
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

// A root folder's free space, "1.5 TB"; `formatNumber(x, decimals)` is the
// locale's (toFixed when left out).
function formatBytes(bytes, formatNumber) {
  if (typeof bytes !== "number" || bytes < 0) return ""
  var units = ["B", "KB", "MB", "GB", "TB", "PB"]
  var v = bytes, u = 0
  while (v >= 1024 && u < units.length - 1) { v /= 1024; u++ }
  var fmt = formatNumber || function(x, d) { return x.toFixed(d) }
  return fmt(v, v >= 100 || u === 0 ? 0 : 1) + " " + units[u]
}
