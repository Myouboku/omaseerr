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
  eq(Notify.parseState("garbage"), { url: "", seen: [], statuses: {}, primed: false })
  const st = Notify.parseState(JSON.stringify({ url: "https://a", seen: [3, "4", -1, 3], statuses: { "5": "pending", "x": "y", "6": 1 }, primed: true }))
  eq(st.seen, [3, 4])
  eq(st.statuses, { 5: "pending" })
  eq(st.primed, true)
})
