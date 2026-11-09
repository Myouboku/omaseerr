import QtQuick
import "../model/values.js" as Values
import "../model/api.js" as Api
import "../model/requests.js" as Requests
import "../model/form.js" as Form

// What can be done to a request: approve (straight away or with the form's
// choices), decline, retry, delete; from a panel, or from IPC and
// notification buttons (actFromOutside). One action per request at a time.
QtObject {
  id: actions
  // The service: the server's origin, open panels, translations.
  required property var svc
  required property var http
  // The requests and the list, updated with each outcome.
  required property var store
  // Counts are polled again after each action.
  required property var poller
  // How to put Seerr's errors in words.
  required property var conn
  // Outcomes of actions taken from outside the panel are notified.
  required property var notifier

  // Request ids with an action in flight.
  property var busy: ({})

  signal actionDone(int requestId, string action, bool ok, string message)

  function isBusy(id) { return busy[id] === true }

  function setBusy(id, on) {
    var next = {}
    for (var k in busy) if (busy[k]) next[k] = true
    if (on) next[id] = true
    else delete next[id]
    busy = next
  }

  // A new connection: what was in flight will never answer.
  function clearBusy() {
    busy = ({})
  }

  // actionDone carries the error on failure and the request's title on
  // success, read before a deleted request is forgotten.
  function afterAction(id, action, res, updated, notify) {
    setBusy(id, false)
    var ok = res.ok
    var message = ok ? "" : conn.describeError(res)
    var known = store.requestById(id) || updated
    var title = known ? store.titleFor(known) : ""
    if (ok) {
      if (action === "delete") {
        store.removeRow(id)
        store.forget(id)
      } else if (updated) {
        store.remember([updated])
        store.updateRow(updated)
        // A row that left the current filter goes once the list refreshes.
      }
      poller.poll()
      if (svc.openPanels > 0) store.refreshListQuietly()
    }
    actionDone(id, action, ok, ok ? title : message)
    if (notify) notifier.announceResult(id, action, ok, message, updated)
  }

  // Seerr's own defaults: no form, straight to approve.
  function quickApprove(id, notify) {
    id = Values.positiveId(id)
    if (!id || isBusy(id)) return false
    setBusy(id, true)
    postStatus(id, "approve", notify)
    return true
  }

  // POST /request/{id}/approve|decline, for an id already marked busy.
  function postStatus(id, action, notify) {
    http.api("POST", "/request/" + id + "/" + action, null, function(res) {
      actions.afterAction(id, action, res, res.ok ? Api.normalizeRequest(res.data) : null, notify)
    })
  }

  // Approve or decline from IPC or a notification button. Seerr sets the
  // status it is asked for whatever the current one is, and a notification
  // stays clickable in the history long after it was sent: the request may
  // have been declined (or approved) since, or the URL may now point to
  // another Seerr. So the request is read first and only a pending one, of
  // the server the notification named, is acted on. The outcome is notified.
  function actFromOutside(target, action) {
    var named = Api.actionTarget(target)
    var id = named.id
    if (!id) return "ignored"
    if (isBusy(id)) return "busy"
    if (named.origin !== "" && named.origin !== svc.keyOrigin) {
      // Not looked up here: the same id names another request on this server.
      var message = conn.describeError({ error: "otherServer" })
      actionDone(id, action, false, message)
      notifier.sendNotification(svc.t("notify.actionFailed").arg("#" + id), message, "", 0, false, "normal")
      return "other server"
    }
    setBusy(id, true)
    store.fetchRequest(id, function(req, res) {
      if (!req) { actions.afterAction(id, action, res.ok ? { ok: false, status: 0, error: "badJson" } : res, null, true); return }
      if (req.status !== Requests.REQUEST_PENDING) {
        actions.afterAction(id, action, { ok: false, status: 0, error: "notPending" }, req, true)
        return
      }
      actions.postStatus(id, action, true)
    })
    return "ok"
  }

  // The advanced path: save the chosen server, profile, folder, tags and
  // seasons on the request, then approve it.
  function approveWithForm(req, form) {
    if (!req || isBusy(req.id)) return false
    if (Form.formProblem(req, form) !== "") return false
    var id = req.id
    setBusy(id, true)
    http.api("PUT", "/request/" + id, Form.updateBody(req, form), function(res) {
      if (!res.ok) { actions.afterAction(id, "approve", res, null, false); return }
      actions.http.api("POST", "/request/" + id + "/approve", null, function(res2) {
        actions.afterAction(id, "approve", res2, res2.ok ? Api.normalizeRequest(res2.data) : null, false)
      })
    })
    return true
  }

  function decline(id, notify) {
    id = Values.positiveId(id)
    if (!id || isBusy(id)) return false
    setBusy(id, true)
    postStatus(id, "decline", notify)
    return true
  }

  function retry(id) {
    id = Values.positiveId(id)
    if (!id || isBusy(id)) return false
    setBusy(id, true)
    http.api("POST", "/request/" + id + "/retry", null, function(res) {
      actions.afterAction(id, "retry", res, res.ok ? Api.normalizeRequest(res.data) : null, false)
    })
    return true
  }

  function remove(id) {
    id = Values.positiveId(id)
    if (!id || isBusy(id)) return false
    setBusy(id, true)
    http.api("DELETE", "/request/" + id, null, function(res) {
      actions.afterAction(id, "delete", res, null, false)
    })
    return true
  }
}
