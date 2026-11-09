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

test("relativeTime edges and default now", () => {
  const words = { now: "now", minutes: n => n + "m", hours: n => n + "h", days: n => n + "d", date: () => "date" }
  const now = Date.parse("2026-11-08T12:00:00Z")
  eq(Time.relativeTime(now - 60e3, now, words), "1m")
  eq(Time.relativeTime(now - 3600e3 + 1, now, words), "59m")
  eq(Time.relativeTime(now - 86400e3, now, words), "1d")
  eq(Time.relativeTime(now - 30 * 86400e3 + 1, now, words), "29d")
  eq(Time.relativeTime(now - 30 * 86400e3, now, words), "date")
  // In the future (a clock ahead of ours): "now", not a negative age.
  eq(Time.relativeTime(now + 3600e3, now, words), "now")
  eq(Time.relativeTime(Date.now() - 5 * 60e3, 0, words), "5m")
})

test("shortDatePattern leaves the year out for this year", () => {
  const now = new Date(2026, 10, 9, 12).getTime()
  eq(Time.shortDatePattern(new Date(2026, 0, 1, 0, 1).getTime(), now), "d MMM")
  eq(Time.shortDatePattern(new Date(2026, 11, 31, 23, 59).getTime(), now), "d MMM")
  eq(Time.shortDatePattern(new Date(2025, 11, 31, 23, 59).getTime(), now), "d MMM yyyy")
  eq(Time.shortDatePattern(new Date(2027, 0, 1).getTime(), now), "d MMM yyyy")
})

test("remaining counts down to a moment ahead", () => {
  const words = { minutes: n => n + "m", hours: n => n + "h", days: n => n + "d" }
  const now = Date.parse("2026-11-08T12:00:00Z")
  eq(Time.remaining(now + 30e3, now, words), "1m")
  eq(Time.remaining(now + 25 * 60e3 - 1, now, words), "25m")
  eq(Time.remaining(now + 2.4 * 3600e3, now, words), "2h")
  eq(Time.remaining(now + 3 * 86400e3, now, words), "3d")
  eq(Time.remaining(now - 1000, now, words), "")
  eq(Time.remaining(0, now, words), "")
})
