// The plugin's settings: their defaults, validating and clamping them (from
// the bar entry or as text from IPC), and finding the bar entry they live in.
// A new setting also goes in manifest.json, pages/SettingsPage.qml and the
// README's table.
.pragma library
.import "values.js" as Values
.import "api.js" as Api
.import "requests.js" as Requests

var PLUGIN_ID = "myouboku.omaseerr"

var DEFAULTS = {
  url: "",
  refreshIntervalSec: 60,
  notifyNewRequests: true,
  notifyStatusChanges: false,
  notifyUrgency: "normal",
  notifyPoster: true,
  notifyGroupThreshold: 3,
  defaultFilter: "pending",
  defaultMediaType: "all",
  defaultSort: "added",
  defaultSortDirection: "desc",
  pageSize: 20,
  showPosters: true,
  confirmDecline: true
}

// Every setting validated and clamped; unknown keys are dropped.
function normalizeSettings(raw) {
  var s = raw && typeof raw === "object" ? raw : {}
  var url = Api.normalizeBaseUrl(s.url)
  return {
    url: url.ok ? url.url : "",
    refreshIntervalSec: Values.clampInt(s.refreshIntervalSec, DEFAULTS.refreshIntervalSec, 15, 3600),
    notifyNewRequests: s.notifyNewRequests === undefined ? DEFAULTS.notifyNewRequests : s.notifyNewRequests === true,
    notifyStatusChanges: s.notifyStatusChanges === true,
    notifyUrgency: Values.oneOf(s.notifyUrgency, ["low", "normal", "critical"], DEFAULTS.notifyUrgency),
    notifyPoster: s.notifyPoster === undefined ? DEFAULTS.notifyPoster : s.notifyPoster === true,
    notifyGroupThreshold: Values.clampInt(s.notifyGroupThreshold, DEFAULTS.notifyGroupThreshold, 1, 20),
    defaultFilter: Values.oneOf(s.defaultFilter, Requests.FILTERS, DEFAULTS.defaultFilter),
    defaultMediaType: Values.oneOf(s.defaultMediaType, Requests.MEDIA_TYPES, DEFAULTS.defaultMediaType),
    defaultSort: Values.oneOf(s.defaultSort, Requests.SORTS, DEFAULTS.defaultSort),
    defaultSortDirection: Values.oneOf(s.defaultSortDirection, Requests.DIRECTIONS, DEFAULTS.defaultSortDirection),
    pageSize: Values.clampInt(s.pageSize, DEFAULTS.pageSize, 5, 100),
    showPosters: s.showPosters === undefined ? DEFAULTS.showPosters : s.showPosters === true,
    confirmDecline: s.confirmDecline === undefined ? DEFAULTS.confirmDecline : s.confirmDecline === true
  }
}

// The value of one setting given as text (from IPC), or undefined when the
// key is unknown or the value does not fit it.
function parseSettingValue(key, text) {
  if (!Object.prototype.hasOwnProperty.call(DEFAULTS, key)) return undefined
  var def = DEFAULTS[key]
  var s = String(text === undefined || text === null ? "" : text).trim()
  if (typeof def === "boolean") {
    if (/^(true|1|on|yes)$/i.test(s)) return true
    if (/^(false|0|off|no)$/i.test(s)) return false
    return undefined
  }
  if (typeof def === "number") {
    if (!/^\d+$/.test(s)) return undefined
    // Refused rather than saved and then silently clamped on read.
    var n = parseInt(s, 10)
    var check = {}
    check[key] = n
    return normalizeSettings(check)[key] === n ? n : undefined
  }
  if (key === "url") {
    if (s === "") return ""
    var u = Api.normalizeBaseUrl(s)
    return u.ok ? u.url : undefined
  }
  var probe = {}
  probe[key] = s
  return normalizeSettings(probe)[key] === s ? s : undefined
}

// This plugin's entry in the bar layout, wherever it was put.
function findBarEntry(barConfig, id) {
  var layout = barConfig && typeof barConfig === "object" && barConfig.layout && typeof barConfig.layout === "object" ? barConfig.layout : null
  if (!layout) return null
  for (var section in layout) {
    var list = layout[section]
    if (!Array.isArray(list)) continue
    for (var i = 0; i < list.length; i++) {
      var entry = list[i]
      if (entry && typeof entry === "object" && entry.id === id) return entry
      if (entry === id) return { id: id }
    }
  }
  return null
}
