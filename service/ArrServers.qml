import QtQuick
import "../model/Seerr.js" as Seerr

// The Radarr and Sonarr servers Seerr knows, and each one's profiles,
// folders and tags, for the approval form. Kept a few minutes: they rarely
// change, and the form is opened request after request.
QtObject {
  id: servers
  required property var http
  // How to put Seerr's errors in words.
  required property var conn

  property var _servers: ({})
  property var _serverDetails: ({})
  readonly property int serviceCacheMs: 5 * 60 * 1000

  // Another server has other Radarr/Sonarr servers, profiles and folders.
  function clear() {
    _servers = ({})
    _serverDetails = ({})
  }

  function serviceType(req) { return req && req.type === "tv" ? "sonarr" : "radarr" }

  function loadServers(type, cb) {
    var cached = _servers[type]
    if (cached && Date.now() - cached.at < serviceCacheMs) { cb(cached.value, null); return }
    http.api("GET", "/service/" + type, null, function(res) {
      if (!res.ok) { cb(null, servers.conn.describeError(res)); return }
      var value = Seerr.normalizeServers(res.data)
      var next = servers._servers
      next[type] = { at: Date.now(), value: value }
      servers._servers = next
      cb(value, null)
    })
  }

  function loadServerDetails(type, serverId, cb) {
    var key = type + ":" + serverId
    var cached = _serverDetails[key]
    if (cached && Date.now() - cached.at < serviceCacheMs) { cb(cached.value, null); return }
    http.api("GET", "/service/" + type + "/" + serverId, null, function(res) {
      if (!res.ok) { cb(null, servers.conn.describeError(res)); return }
      var value = Seerr.normalizeServerDetails(res.data)
      var next = servers._serverDetails
      next[key] = { at: Date.now(), value: value }
      servers._serverDetails = next
      cb(value, null)
    })
  }
}
