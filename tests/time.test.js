// Tests for model/time.js.

const { load, test, eq } = require("./harness")
const Time = load("model/time.js")

test("relativeTime", () => {
  const words = { now: "now", minutes: n => n + "m", hours: n => n + "h", days: n => n + "d", date: () => "date" }
  const now = Date.parse("2026-11-08T12:00:00Z")
  eq(Time.relativeTime(now - 30e3, now, words), "now")
  eq(Time.relativeTime(now - 5 * 60e3, now, words), "5m")
  eq(Time.relativeTime(now - 3 * 3600e3, now, words), "3h")
  eq(Time.relativeTime(now - 2 * 86400e3, now, words), "2d")
  eq(Time.relativeTime(now - 90 * 86400e3, now, words), "date")
  eq(Time.relativeTime(0, now, words), "")
})
