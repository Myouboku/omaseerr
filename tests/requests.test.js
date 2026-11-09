// Tests for model/requests.js.

const { load, fixture, test, eq } = require("./harness")
const Api = load("model/api.js")
const Requests = load("model/requests.js")

const list = Api.normalizeRequestList(JSON.parse(fixture("requests.json")))

test("statusKey combines request and media status", () => {
  const k = (status, mediaStatus) => Requests.statusKey({ status, mediaStatus })
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
  eq(Requests.statusColor("pending"), "")
  eq(Requests.statusColor("available"), "#22c55e")
  eq(Requests.statusColor("processing"), "#6366f1")
  eq(Requests.statusColor("declined"), "#dc2626")
  eq(Requests.statusColor("failed"), "#dc2626")
  eq(Requests.statusColor("nope"), "dim")
})

test("matchesView: declined client filter and search", () => {
  const media = { title: "Inception", year: "2010" }
  eq(Requests.matchesView(list.requests[3], { filter: "declined" }, null), true)
  eq(Requests.matchesView(list.requests[2], { filter: "declined" }, null), false)
  eq(Requests.matchesView(list.requests[2], { filter: "all", search: "incep 2010" }, media), true)
  eq(Requests.matchesView(list.requests[2], { filter: "all", search: "alice" }, media), true)
  eq(Requests.matchesView(list.requests[2], { filter: "all", search: "matrix" }, media), false)
})

test("mergePage keeps order and drops duplicates", () => {
  eq(Requests.mergePage([{ id: 1 }, { id: 2 }], [{ id: 2 }, { id: 3 }]).map(r => r.id), [1, 2, 3])
  eq(Requests.removeRequest([{ id: 1 }, { id: 2 }], 1).map(r => r.id), [2])
  eq(Requests.replaceRequest([{ id: 1, a: 1 }], { id: 1, a: 2 }), [{ id: 1, a: 2 }])
})

test("seasonsLabel collapses runs", () => {
  eq(Requests.seasonsLabel([1, 2, 3, 5, 7, 8]), "1–3, 5, 7–8")
  eq(Requests.seasonsLabel([4]), "4")
  eq(Requests.seasonsLabel([]), "")
})

test("nextValue goes round both ways", () => {
  const v = ["a", "b", "c"]
  eq(Requests.nextValue(v, "a", false), "b")
  eq(Requests.nextValue(v, "c", false), "a")
  eq(Requests.nextValue(v, "a", true), "c")
  eq(Requests.nextValue(v, "b", true), "a")
  // An unknown value sits just before the first.
  eq(Requests.nextValue(v, "zz", false), "a")
  eq(Requests.nextValue(v, "zz", true), "b")
  eq(Requests.nextValue(["only"], "only", true), "only")
})

test("sortChoices pair every sort with every direction", () => {
  const c = Requests.sortChoices()
  eq(c.map(x => x.value), ["added:desc", "added:asc", "modified:desc", "modified:asc"])
  eq(c[2], { value: "modified:desc", sort: "modified", direction: "desc" })
  eq(c.length, Requests.SORTS.length * Requests.DIRECTIONS.length)
})

test("sortChoice and sortPatch round-trip a view", () => {
  eq(Requests.sortChoice({ sort: "modified", sortDirection: "asc", filter: "all" }), "modified:asc")
  eq(Requests.sortChoice(null), "added:desc")
  eq(Requests.sortPatch("modified:asc"), { sort: "modified", sortDirection: "asc" })
  for (const c of Requests.sortChoices()) eq(Requests.sortChoice(Requests.sortPatch(c.value)), c.value)
})

test("emptyListKey: search first, then the view", () => {
  const k = (filter, mediaType, search) => Requests.emptyListKey({ filter, mediaType, search })
  eq(k("pending", "all", "dune"), "list.noMatch")
  eq(k("all", "tv", "dune"), "list.noMatch")
  eq(k("pending", "all", ""), "list.nothingPending")
  eq(k("pending", "movie", ""), "list.emptyFilter")
  eq(k("all", "all", ""), "list.noRequests")
  eq(k("all", "tv", ""), "list.emptyFilter")
  eq(k("declined", "all", undefined), "list.emptyFilter")
})
