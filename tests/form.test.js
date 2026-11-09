// Tests for model/form.js.

const { load, fixture, test, eq } = require("./harness")
const Api = load("model/api.js")
const Form = load("model/form.js")

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

test("pickServer honours request, then default for 4K-ness", () => {
  const hd = { is4k: false, serverId: -1 }
  eq(Form.pickServer(servers, hd).id, 0)
  eq(Form.pickServer(servers, { is4k: true, serverId: -1 }).id, 1)
  eq(Form.pickServer(servers, { is4k: false, serverId: 1 }).id, 1)
  eq(Form.pickServer([], hd), null)
})

test("formServers offers the picked server even of the other 4K-ness", () => {
  eq(Form.formServers(servers, { is4k: false, serverId: -1 }).map(s => s.id), [0])
  eq(Form.formServers(servers, { is4k: true, serverId: -1 }).map(s => s.id), [1])
  eq(Form.formServers(servers, { is4k: false, serverId: 1 }).map(s => s.id), [1, 0])
  eq(Form.formServers([], { is4k: false, serverId: -1 }), [])
})

test("defaultForm uses request values, then (anime) server defaults", () => {
  const req = list.requests[1] // tv 4K, server 1, profile 6
  const form = Form.defaultForm(req, servers[1], details, false)
  eq(form.profileId, 6)
  eq(form.rootFolder, "/tv4k")
  eq(form.seasons, [1, 2, 3])
  const plain = Object.assign({}, req, { serverId: -1, profileId: -1, rootFolder: "", languageProfileId: -1, tags: [] })
  const anime = Form.defaultForm(plain, servers[0], details, true)
  eq([anime.profileId, anime.rootFolder, anime.languageProfileId, anime.tags], [5, "/anime", 2, [3]])
  const normal = Form.defaultForm(plain, servers[0], details, false)
  eq([normal.profileId, normal.rootFolder, normal.languageProfileId, normal.tags], [4, "/tv", 1, [1]])
})

test("defaultForm falls back when defaults are unknown to the server", () => {
  const req = Object.assign({}, list.requests[0])
  const odd = Object.assign({}, servers[0], { activeProfileId: 99, activeDirectory: "/gone", activeTags: [42] })
  const form = Form.defaultForm(req, odd, details, false)
  eq([form.profileId, form.rootFolder, form.tags], [4, "/tv", []])
  eq(Form.defaultForm(req, null, null, false).serverId, -1)
})

test("formProblem and updateBody", () => {
  const tv = list.requests[1]
  const form = { serverId: 1, profileId: 6, rootFolder: "/tv4k", languageProfileId: 1, tags: [1], seasons: [3, 1] }
  eq(Form.formProblem(tv, form), "")
  eq(Form.formProblem(tv, Object.assign({}, form, { seasons: [] })), "noSeasons")
  eq(Form.formProblem(tv, Object.assign({}, form, { rootFolder: "" })), "noRootFolder")
  eq(Form.formProblem(tv, null), "noServer")
  eq(Form.updateBody(tv, form), { mediaType: "tv", serverId: 1, profileId: 6, rootFolder: "/tv4k", tags: [1], seasons: [1, 3], languageProfileId: 1 })
  eq(Form.updateBody(list.requests[0], form), { mediaType: "movie", serverId: 1, profileId: 6, rootFolder: "/tv4k", tags: [1] })
})

test("toggleInList", () => {
  eq(Form.toggleInList([1, 3], 2), [1, 2, 3])
  eq(Form.toggleInList([1, 3], 3), [1])
})

test("formatBytes", () => {
  eq(Form.formatBytes(1536), "1.5 KB")
  eq(Form.formatBytes(2 * 1024 ** 4), "2.0 TB")
  eq(Form.formatBytes(-1), "")
})
