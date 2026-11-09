import QtQuick
import "../model/Seerr.js" as Seerr

// The approval form of one panel: the request, the Radarr/Sonarr servers
// and the chosen server's options, and the choices made so far.
QtObject {
  id: approval
  // The panel: service, state (nav), translations.
  required property var ctx
  readonly property var svc: ctx.svc

  property var req: null
  property var servers: []
  property var details: null
  property var form: null
  property bool loading: false
  property string error: ""
  readonly property var media: req && svc ? (svc.mediaRevision, svc.mediaFor(req)) : null

  function start(r) {
    req = r
    ctx.nav.showRequest(r)
    servers = []
    details = null
    form = null
    error = ""
    loading = true
    ctx.nav.go("approve")
    var type = svc.serviceType(r)
    svc.ensureMedia(r, function(m) {
      approval.svc.loadServers(type, function(list, error) {
        if (approval.req !== r) return
        if (error) { approval.loading = false; approval.error = error; return }
        approval.servers = Seerr.formServers(list, r)
        var server = Seerr.pickServer(list, r)
        if (!server) { approval.loading = false; approval.error = approval.ctx.t("approve.noServers"); return }
        approval.selectServer(server.id, m)
      })
    })
  }

  function selectServer(serverId, m) {
    var r = req
    var server = null
    var all = servers
    for (var i = 0; i < all.length; i++) if (all[i].id === serverId) server = all[i]
    if (!server) { loading = false; error = ctx.t("approve.noServers"); return }
    loading = true
    error = ""
    svc.loadServerDetails(svc.serviceType(r), server.id, function(d, error) {
      if (approval.req !== r) return
      approval.loading = false
      if (error) { approval.error = error; return }
      var media = m !== undefined ? m : approval.media
      var seasons = approval.form && approval.form.seasons ? approval.form.seasons : null
      approval.details = d
      var f = Seerr.defaultForm(r, server, d, !!(media && media.anime))
      if (seasons) f.seasons = seasons
      approval.form = f
    })
  }

  function set(patch) {
    var next = {}
    for (var k in form) next[k] = form[k]
    for (var p in patch) next[p] = patch[p]
    form = next
  }

  function submit(quick) {
    if (!req || !svc) return
    if (quick) { svc.quickApprove(req.id, false); ctx.nav.go("detail"); return }
    var problem = Seerr.formProblem(req, form)
    if (problem) { ctx.nav.flash(ctx.t("approve.problem." + problem), true); return }
    svc.approveWithForm(req, form)
  }
}
