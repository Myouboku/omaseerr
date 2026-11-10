import QtQuick
import "../model/form.js" as Form

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
        approval.servers = Form.formServers(list, r)
        var server = Form.pickServer(list, r)
        if (!server) { approval.loading = false; approval.error = approval.ctx.t("approve.noServers"); return }
        approval.selectServer(server.id, m)
      })
    })
  }

  property Connections _service: Connections {
    target: approval.svc
    ignoreUnknownSignals: true
    // Another URL is another server, where the same id names an unrelated
    // request: the form is dropped, so nothing of it can be submitted there
    // (the panel leaves the page, see PanelState).
    function onBaseUrlChanged() { approval.clear() }
    // Calls under way when Seerr went down are dropped on the retry: a form
    // still loading starts over once Seerr answers again.
    function onConnectionChanged() {
      if (approval.svc.connection === "connected" && approval.loading && approval.req && approval.ctx.nav.page === "approve")
        approval.start(approval.req)
    }
  }

  function clear() {
    req = null
    servers = []
    details = null
    form = null
    loading = false
    error = ""
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
      var f = Form.defaultForm(r, server, d, !!(media && media.anime))
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
    var problem = Form.formProblem(req, form)
    if (problem) { ctx.nav.flash(ctx.t("approve.problem." + problem), true); return }
    svc.approveWithForm(req, form)
  }
}
