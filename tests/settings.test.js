// Tests for model/settings.js.

const { load, test, eq } = require("./harness")
const Settings = load("model/settings.js")

test("parseSettingValue", () => {
  eq(Settings.parseSettingValue("notifyPoster", "off"), false)
  eq(Settings.parseSettingValue("notifyPoster", "maybe"), undefined)
  eq(Settings.parseSettingValue("pageSize", "30"), 30)
  eq(Settings.parseSettingValue("pageSize", "-3"), undefined)
  eq(Settings.parseSettingValue("defaultFilter", "declined"), "declined")
  eq(Settings.parseSettingValue("defaultFilter", "bogus"), undefined)
  eq(Settings.parseSettingValue("url", "seerr.lan:5055/"), "https://seerr.lan:5055")
  eq(Settings.parseSettingValue("url", "ftp://x"), undefined)
  eq(Settings.parseSettingValue("nope", "1"), undefined)
  eq(Settings.parseSettingValue("__proto__", "1"), undefined)
})

test("normalizeSettings clamps and defaults", () => {
  const s = Settings.normalizeSettings({ url: "seerr.lan/", refreshIntervalSec: 2, defaultFilter: "nope", pageSize: "50", notifyNewRequests: false, extra: 1 })
  eq(s.url, "https://seerr.lan")
  eq(s.refreshIntervalSec, 15)
  eq(s.defaultFilter, "pending")
  eq(s.pageSize, 50)
  eq(s.notifyNewRequests, false)
  eq(s.showPosters, true)
  eq("extra" in s, false)
  eq(Settings.normalizeSettings(null).url, "")
  eq(Settings.normalizeSettings({ url: "ftp://x" }).url, "")
})

test("findBarEntry searches every section", () => {
  const cfg = { layout: { left: [{ id: "a" }], right: [{ id: "myouboku.omaseerr", url: "x" }] } }
  eq(Settings.findBarEntry(cfg, "myouboku.omaseerr"), { id: "myouboku.omaseerr", url: "x" })
  eq(Settings.findBarEntry({ layout: { tray: ["myouboku.omaseerr"] } }, "myouboku.omaseerr"), { id: "myouboku.omaseerr" })
  eq(Settings.findBarEntry({}, "x"), null)
})
