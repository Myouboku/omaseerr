// Tests for model/notify.js.

const { load, fixture, test, eq } = require("./harness")
const Api = load("model/api.js")
const Notify = load("model/notify.js")

const list = Api.normalizeRequestList(JSON.parse(fixture("requests.json")))

test("newRequestIds and rememberIds", () => {
  eq(Notify.newRequestIds([11, 10], list.requests.slice(0, 2)), [12])
  eq(Notify.rememberIds([1, 2], [3, 2]), [3, 2, 1])
  const many = Array.from({ length: 1500 }, (_, i) => i + 1)
  eq(Notify.rememberIds([], many).length, Notify.MAX_SEEN)
})

test("statusChanges reports available and failed transitions only", () => {
  const prev = { 10: "processing", 9: "pending", 12: "pending" }
  const changes = Notify.statusChanges(prev, list.requests)
  eq(changes, [{ id: 10, from: "processing", to: "available" }])
  eq(Notify.statusMap(list.requests)[9], "declined")
})

test("neutralizeMarkup survives the daemon's entity decoding", () => {
  const out = Notify.neutralizeMarkup("<b>x</b> &lt;i&gt; &amp;")
  // Mirror of the daemon: decode entities, escape, restore allowed tags.
  const decoded = out.replace(/&(lt|gt|amp);/g, (_, n) => ({ lt: "<", gt: ">", amp: "&" })[n])
  eq(/<b>|<i>|<\/b>/.test(decoded), false)
  eq(out.replace(/\u2060/g, ""), "<b>x</b> &lt;i&gt; &amp;")
})

test("parseState is defensive", () => {
  eq(Notify.parseState("garbage"), { url: "", seen: [], statuses: {}, primed: false, tracking: false })
  const st = Notify.parseState(JSON.stringify({ url: "https://a", seen: [3, "4", -1, 3], statuses: { "5": "pending", "x": "y", "6": 1 }, primed: true }))
  eq(st.seen, [3, 4])
  eq(st.statuses, { 5: "pending" })
  eq(st.primed, true)
  eq(st.tracking, false)
  eq(Notify.parseState(JSON.stringify({ tracking: true })).tracking, true)
  eq(Notify.parseState(JSON.stringify({ tracking: "yes" })).tracking, false)
})

test("mergeStatuses keeps what left the recent window and drops settled ones", () => {
  const req = (id, status, mediaStatus) => ({ id, status, media: { status: mediaStatus || 0 } })
  const pending = req(1, 1), approved = req(2, 2, 3)
  // 7 was processing and is no longer among the recent ones: kept.
  const merged = Notify.mergeStatuses({ 7: "processing", 8: "available" }, [pending, approved])
  eq(merged[7], "processing")
  eq(merged[1], Notify.statusMap([pending])[1])
  eq(merged[2], Notify.statusMap([approved])[2])
  // Settled statuses are not watched any more.
  eq(merged[8], undefined)
  // A watched request that settles leaves the map.
  const settled = Notify.statusMap([req(9, 3)])[9]
  if (["available", "completed", "declined", "deleted"].indexOf(settled) !== -1)
    eq(Notify.mergeStatuses({ 9: "processing" }, [req(9, 3)])[9], undefined)
  // Too many: the newest ids stay.
  const many = {}
  for (let i = 1; i <= 600; i++) many[i] = "processing"
  const capped = Notify.mergeStatuses(many, [])
  eq(Object.keys(capped).length, 500)
  eq(capped[600], "processing")
  eq(capped[100], undefined)
})
