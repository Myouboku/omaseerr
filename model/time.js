// Dates for display. The words and the locale formatting stay in QML; this
// decides which to use.
.pragma library

// "3 min", "2 h", "5 d", or a date for anything older than a month. `words`
// carries the translated units: { now, minutes, hours, days } where each
// takes %1, plus `date(ms)` for old ones.
function relativeTime(ms, now, words) {
  if (!ms) return ""
  var diff = Math.max(0, (now || Date.now()) - ms)
  var minute = 60000, hour = 3600000, day = 86400000
  if (diff < minute) return words.now
  if (diff < hour) return words.minutes(Math.floor(diff / minute))
  if (diff < day) return words.hours(Math.floor(diff / hour))
  if (diff < 30 * day) return words.days(Math.floor(diff / day))
  return words.date(ms)
}

// The date pattern of a short date: the year only when it is not this one
// ("9 Nov" or "9 Nov 2025"), in local time.
function shortDatePattern(ms, now) {
  var sameYear = new Date(ms).getFullYear() === new Date(now || Date.now()).getFullYear()
  return sameYear ? "d MMM" : "d MMM yyyy"
}
