import QtQuick
import "../model/Seerr.js" as Seerr

// The connection to Seerr: who we are on it (me, canManage), whether it
// answers, and since when it does not. reconnect() starts it over, which
// drops whatever the previous one had loaded unless it is a retry.
QtObject {
  id: conn
  // The service: URL, open panels, translations.
  required property var svc
  required property var http
  // Whether the key may go to the URL.
  required property var keyring
  // What a connection loads, cleared when it starts over.
  required property var poller
  required property var store
  required property var actions
  required property var servers

  // "unconfigured" | "connecting" | "connected" | "error"
  property string state: "unconfigured"
  property string lastError: ""
  // When Seerr last answered, so an outage can say since when.
  property double lastOkAt: 0
  property var me: null
  property bool canManage: true

  // `retry` is a new attempt at the same server after an error: what was
  // already shown stays (greyed by the panel) instead of going blank.
  function reconnect(retry) {
    http.reset()
    poller.stop()
    store.stopLoading()
    actions.clearBusy()
    if (retry === true && state === "error" && keyring.matches(svc.baseUrl)) {
      state = "connecting"
      http.api("GET", "/auth/me", null, conn.onAuthAnswer)
      return
    }
    me = null
    poller.clear()
    store.clear()
    servers.clear()
    if (!keyring.matches(svc.baseUrl)) {
      state = "unconfigured"
      lastError = ""
      return
    }
    state = "connecting"
    lastError = ""
    lastOkAt = 0
    http.api("GET", "/auth/me", null, conn.onAuthAnswer)
  }

  function onAuthAnswer(res) {
    if (!res.ok) { fail(res); return }
    me = Seerr.normalizeUser(res.data)
    var perms = res.data && typeof res.data.permissions === "number" ? res.data.permissions : 0
    // ADMIN (2) or MANAGE_REQUESTS (16).
    canManage = (perms & 2) !== 0 || (perms & 16) !== 0
    state = "connected"
    lastError = ""
    lastOkAt = Date.now()
    poller.poll()
    if (svc.openPanels > 0) store.reloadList()
  }

  function fail(res) {
    state = "error"
    lastError = describeError(res)
  }

  function describeError(res) {
    if (!res) return svc.t("error.unknown")
    if (res.error === "notConfigured") return svc.t("error.notConfigured")
    if (res.error === "timeout") return svc.t("error.timeout")
    if (res.error === "network") return svc.t("error.network")
    if (res.error === "badJson" || res.error === "tooLarge") return svc.t("error.badResponse")
    if (res.error === "tls") return svc.t("error.tls")
    if (res.error === "notPending") return svc.t("error.conflict")
    if (res.error === "otherServer") return svc.t("error.otherServer")
    if (res.error === "redirect") return res.location ? svc.t("error.redirectTo").arg(res.location) : svc.t("error.redirect")
    if (res.status === 401 || res.status === 403) return svc.t("error.unauthorized")
    if (res.status === 404) return svc.t("error.notFound")
    if (res.status === 409) return res.message || svc.t("error.conflict")
    return res.message ? res.message : svc.t("error.http").arg(res.status)
  }
}
