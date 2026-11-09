import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import "model/Seerr.js" as Seerr
import "service"

// The one OmaSeerr instance per shell. It owns the connection (URL from the
// bar entry's settings, API key from the keyring), polls Seerr, announces new
// requests, runs the request actions, and answers IPC. Bar widgets — one per
// monitor — only draw what this holds, so nothing here is ever doubled.
// This file keeps the settings, the translations and IPC, creates the parts
// under service/ (they read settings and translations through `svc`, this
// object), and forwards to them what the panels use.
Item {
  id: root

  // Injected by the shell.
  property var shell: null
  property var manifest: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"

  readonly property string pluginId: Seerr.PLUGIN_ID

  // ---------------------------------------------------------------- settings

  // Our entry in the bar layout is where the settings live. The bar hands the
  // widget its entry live on every change, and the widget passes it here; the
  // copy of the bar config the shell gave the service is only refreshed when
  // plugins reload, so it serves only until a widget reports in.
  property var widgetSettings: null
  readonly property var entry: widgetSettings ? widgetSettings
    : (shell && shell.barConfig ? Seerr.findBarEntry(shell.barConfig, pluginId) : null)
  readonly property var settings: Seerr.normalizeSettings(entry || {})
  readonly property string baseUrl: settings.url
  // Where the API key may go: the keyring holds one key per origin.
  readonly property string keyOrigin: Seerr.keyOrigin(baseUrl)
  readonly property bool insecure: baseUrl.indexOf("http://") === 0
  // Plain HTTP to something outside the local network: worth a warning.
  readonly property bool exposed: insecure && !Seerr.isPrivateHost(baseUrl)
  readonly property bool canSaveSettings: !!shell && typeof shell.updateEntryInline === "function"

  function saveSettings(patch) {
    if (!canSaveSettings) return false
    var next = {}
    var current = entry || {}
    for (var k in current) if (k !== "id") next[k] = current[k]
    for (var p in patch) next[p] = patch[p]
    return shell.updateEntryInline(pluginId, next)
  }

  // ---------------------------------------------------------------- i18n

  Commons.Translations {
    id: catalog
    directory: Qt.resolvedUrl("i18n")
  }
  // Exposed so the panels translate from the same catalog.
  readonly property var strings: catalog
  function t(key) { return catalog.t(key) }
  function tn(key, n) { return catalog.tn(key, n).arg(Commons.I18n.formatNumber(n)) }

  // ---------------------------------------------------------------- panels

  // Panels open across monitors; while any is, the list follows each poll.
  property int openPanels: 0
  // A request a notification or IPC asked to show; the panel that opens
  // takes it and clears it.
  property int focusRequestId: 0

  // ---------------------------------------------------------------- parts

  // The API key in the keyring; each lookup starts the connection over.
  Keyring {
    id: keyring
    svc: root
    onLoaded: conn.reconnect()
  }

  Http {
    id: http
    svc: root
    keyring: keyring
  }

  Connection {
    id: conn
    svc: root
    http: http
    keyring: keyring
    poller: poller
    store: store
    actions: actions
    servers: servers
  }

  Poller {
    id: poller
    svc: root
    http: http
    conn: conn
    store: store
    stateFile: stateFile
    onArrived: function(requests) { notifier.announceArrivals(requests) }
    onStatusReached: function(request, statusKey) { notifier.announceStatus(request, statusKey) }
  }

  RequestStore {
    id: store
    svc: root
    http: http
    conn: conn
  }

  Actions {
    id: actions
    svc: root
    http: http
    store: store
    poller: poller
    conn: conn
    notifier: notifier
    onActionDone: function(requestId, action, ok, message) { root.actionDone(requestId, action, ok, message) }
  }

  ArrServers {
    id: servers
    http: http
    conn: conn
  }

  Notifier {
    id: notifier
    svc: root
    store: store
    canManage: conn.canManage
    posterDir: stateFile.cacheDir + "/posters"
    postersReady: stateFile.dirsReady
  }

  StateFile {
    id: stateFile
    onRead: poller.poll()
  }

  // ---------------------------------------------------------------- lifecycle

  Component.onCompleted: {
    stateFile.prepare()
    keyring.load()
  }

  onBaseUrlChanged: conn.reconnect()
  // Another server: its key, or none, never the previous one's.
  onKeyOriginChanged: keyring.load()

  // ---------------------------------------------------------------- panels' API

  // "unconfigured" | "connecting" | "connected" | "error"
  readonly property alias connection: conn.state
  readonly property alias lastError: conn.lastError
  readonly property alias lastOkAt: conn.lastOkAt
  readonly property alias me: conn.me
  readonly property alias canManage: conn.canManage
  readonly property alias counts: poller.counts

  // "loading" | "missing" | "ok" | "error"
  readonly property alias keyState: keyring.state
  readonly property alias keyMessage: keyring.message
  function storeKey(key) { return keyring.store(key) }
  function clearKey() { keyring.clear() }

  function refresh() { poller.refresh() }

  readonly property alias view: store.view
  readonly property alias rows: store.rows
  readonly property alias listLoading: store.listLoading
  readonly property alias listError: store.listError
  readonly property alias mediaRevision: store.mediaRevision
  readonly property alias knownRevision: store.knownRevision
  function setView(patch) { store.setView(patch) }
  function reloadList() { store.reloadList() }
  function loadMore() { store.loadMore() }
  function rowById(id) { return store.rowById(id) }
  function requestById(id) { return store.requestById(id) }
  function fetchRequest(id, cb) { store.fetchRequest(id, cb) }
  function mediaFor(req) { return store.mediaFor(req) }
  function ensureMedia(req, cb) { store.ensureMedia(req, cb) }
  function nameFor(req) { return store.nameFor(req) }
  function yearFor(req) { return store.yearFor(req) }
  function titleFor(req) { return store.titleFor(req) }

  signal actionDone(int requestId, string action, bool ok, string message)
  function isBusy(id) { return actions.isBusy(id) }
  function quickApprove(id, notify) { return actions.quickApprove(id, notify) }
  function approveWithForm(req, form) { return actions.approveWithForm(req, form) }
  function decline(id, notify) { return actions.decline(id, notify) }
  function retry(id) { return actions.retry(id) }
  function remove(id) { return actions.remove(id) }

  function serviceType(req) { return servers.serviceType(req) }
  function loadServers(type, cb) { servers.loadServers(type, cb) }
  function loadServerDetails(type, serverId, cb) { servers.loadServerDetails(type, serverId, cb) }

  function openInBrowser(req) {
    if (!baseUrl) return
    var url = req ? Seerr.webUrl(baseUrl, req.type, req.tmdbId) : baseUrl + "/requests"
    Qt.openUrlExternally(url)
  }

  // ---------------------------------------------------------------- IPC

  // Opens the panel on the focused monitor; the shell picks which copy.
  function openPanel() {
    if (!shell || typeof shell.summon !== "function") return "no shell"
    return shell.summon(pluginId, "{}") ? "ok" : "not summoned"
  }

  // A request of another server than the one now configured is not shown:
  // its id would open an unrelated request here.
  function showRequest(target) {
    var named = Seerr.actionTarget(target)
    focusRequestId = named.origin === "" || named.origin === keyOrigin ? named.id : 0
    return openPanel()
  }

  function statusLine() {
    if (connection === "connected") return "connected pending=" + counts.pending + " total=" + counts.total
    if (connection === "unconfigured") return !baseUrl ? "unconfigured: no url" : "unconfigured: no api key"
    return connection + (lastError ? ": " + lastError : "")
  }

  ShellIpc {
    target: Seerr.PLUGIN_ID

    function ping(): string { return "ok" }
    function status(): string { return root.statusLine() }
    function pending(): string { return String(root.counts.pending) }
    function refresh(): string { root.refresh(); return "ok" }
    function open(): string { root.focusRequestId = 0; return root.openPanel() }
    function toggle(): string { if (root.shell) root.shell.toggle(root.pluginId, "{}"); return "ok" }
    function show(id: string): string { return root.showRequest(id) }
    function approve(id: string): string { return actions.actFromOutside(id, "approve") }
    function decline(id: string): string { return actions.actFromOutside(id, "decline") }
    function reloadKey(): string { keyring.load(); return "ok" }
    // omarchy-shell myouboku.omaseerr set notifyStatusChanges true
    function set(key: string, value: string): string {
      var v = Seerr.parseSettingValue(key, value)
      if (v === undefined) return "invalid"
      var patch = {}
      patch[key] = v
      return root.saveSettings(patch) ? "ok" : "not saved"
    }
    function get(key: string): string {
      return Object.prototype.hasOwnProperty.call(root.settings, key) ? String(root.settings[key]) : "unknown"
    }
  }
}
