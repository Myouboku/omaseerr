import QtQuick
import Quickshell
import Quickshell.Io
import "../model/api.js" as Api
import "../model/requests.js" as Requests
import "../model/notify.js" as Notify

// Desktop notifications: new requests (with Details, Approve and Decline
// buttons), status changes, and the outcome of actions taken from outside
// the panel. Posters are downloaded to a cache first: the daemon wants a
// file.
QtObject {
  id: notifier
  // The service: settings, the server's origin, translations.
  required property var svc
  // Media details and titles, and requests not loaded yet.
  required property var store
  // Whether the user may approve and decline, so whether to offer it.
  property bool canManage: false
  // Where posters are cached, once the folder exists.
  property string posterDir: ""
  property bool postersReady: false

  readonly property string shellCli: svc.omarchyPath + "/bin/omarchy-shell"
  readonly property string glyph: "\u{f0fce}"
  // TEMPORARY, until Omarchy can send a notification without its text on a
  // command line (see "Temporary" in AGENTS.md): omarchy-notification-send
  // takes it as arguments, and so does the busctl it runs, where any local
  // account can read it. This helper reads it on stdin and talks to the bus.
  readonly property string sender: decodeURIComponent(String(Qt.resolvedUrl("dbus-notify.pl")).replace(/^file:\/\//, ""))

  function sendNotification(summary, body, imagePath, requestId, withActions, urgency) {
    var spec = { app: "Seerr", glyph: glyph, urgency: urgency || svc.settings.notifyUrgency,
      summary: summary, body: body, image: imagePath }
    // The request, and the server it is on: see Actions.actFromOutside.
    var target = String(requestId) + (svc.keyOrigin ? "@" + svc.keyOrigin : "")
    if (withActions && requestId > 0) {
      // The card's own click runs the first action, so the harmless one leads.
      spec.actions = [{ label: svc.t("notify.details"), argv: [shellCli, svc.pluginId, "show"] }]
      if (canManage) {
        spec.actions.push({ label: svc.t("notify.approve"), argv: [shellCli, svc.pluginId, "approve"] })
        spec.actions.push({ label: svc.t("notify.decline"), argv: [shellCli, svc.pluginId, "decline"] })
      }
      spec["with"] = [target]
    } else if (requestId > 0) {
      spec.exec = [shellCli, svc.pluginId, "show", target]
    } else if (requestId === -1) {
      spec.exec = [shellCli, svc.pluginId, "open"]
    }
    var proc = senderProcess.createObject(notifier, { payload: JSON.stringify(Notify.notification(spec)) })
    if (proc) proc.running = true
  }

  property Component _sender: Component {
    id: senderProcess
    Process {
      id: proc
      property string payload: ""
      command: ["perl", notifier.sender]
      stdinEnabled: true
      onStarted: {
        // The notification goes in on stdin; closing it ends the read.
        write(proc.payload)
        proc.payload = ""
        proc.stdinEnabled = false
      }
      onExited: function(code) {
        if (code !== 0) console.warn("omaseerr: a notification could not be sent (dbus-notify.pl exited " + code + ")")
        Qt.callLater(function() { proc.destroy() })
      }
    }
  }

  function requestLine(req) {
    var parts = []
    if (req.requestedBy) parts.push(svc.t("notify.by").arg(req.requestedBy.name))
    parts.push(req.type === "tv" ? svc.t("type.tv") : svc.t("type.movie"))
    if (req.is4k) parts.push("4K")
    if (req.type === "tv" && req.seasons.length) parts.push(svc.t("detail.seasonsShort").arg(Requests.seasonsLabel(req.seasons)))
    return parts.join(" · ")
  }

  // Requests that just arrived, oldest first on screen: one notification
  // each, or a single one for the lot past the grouping threshold.
  function announceArrivals(list) {
    if (!svc.settings.notifyNewRequests) return
    // A threshold of 1 means never group.
    var threshold = svc.settings.notifyGroupThreshold
    if (threshold > 1 && list.length >= threshold) announceMany(list)
    else for (var i = list.length - 1; i >= 0; i--) announceNew(list[i])
  }

  function announceNew(req) {
    store.ensureMedia(req, function(m) {
      var summary = notifier.svc.t("notify.newRequest").arg(notifier.store.titleFor(req))
      notifier.withPoster(m, function(path) {
        notifier.sendNotification(summary, notifier.requestLine(req), path, req.id, true)
      })
    })
  }

  function announceMany(list) {
    sendNotification(svc.tn("notify.newRequests", list.length), svc.t("notify.openPanel"), "", -1, false)
  }

  function announceStatus(req, statusKey) {
    store.ensureMedia(req, function(m) {
      var summary = (statusKey === "available" ? notifier.svc.t("notify.available") : notifier.svc.t("notify.failed")).arg(notifier.store.titleFor(req))
      notifier.withPoster(m, function(path) {
        notifier.sendNotification(summary, notifier.requestLine(req), path, req.id, false,
          statusKey === "failed" ? "normal" : "low")
      })
    })
  }

  function announceResult(id, action, ok, message, updated) {
    var finish = function(req) {
      var title = req ? notifier.store.titleFor(req) : ("#" + id)
      if (ok) {
        var key = action === "approve" ? "notify.approved" : "notify.declined"
        notifier.sendNotification(notifier.svc.t(key).arg(title), "", "", req ? req.id : 0, false, "low")
      } else {
        notifier.sendNotification(notifier.svc.t("notify.actionFailed").arg(title), message, "", id, false, "normal")
      }
    }
    if (updated) store.ensureMedia(updated, function() { finish(updated) })
    else store.fetchRequest(id, function(req) {
      if (req) notifier.store.ensureMedia(req, function() { finish(req) })
      else finish(null)
    })
  }

  // Posters for notifications are cached files: the daemon wants a path.
  property var _posterQueue: []

  function withPoster(m, cb) {
    var url = m && svc.settings.notifyPoster ? Api.posterUrl(m.posterPath, "w185") : ""
    if (!url || !postersReady) { cb(""); return }
    var file = posterDir + "/" + m.posterPath.slice(1)
    _posterQueue.push({ url: url, file: file, cb: cb })
    if (!posterFetch.running) nextPoster()
  }

  function nextPoster() {
    if (_posterQueue.length === 0) return
    var job = _posterQueue[0]
    posterFetch.job = job
    posterFetch.command = ["bash", "-c",
      "[[ -s $1 ]] && exit 0\n" +
      "tmp=$1.part\n" +
      "curl -sfL --proto =https --max-time 10 --max-filesize 3000000 -o \"$tmp\" -- \"$2\" && mv -f -- \"$tmp\" \"$1\" || { rm -f -- \"$tmp\"; exit 1; }",
      "omaseerr-poster", job.file, job.url]
    posterFetch.running = true
  }

  property Process _poster: Process {
    id: posterFetch
    property var job: null
    onExited: function(code) {
      var job = posterFetch.job
      notifier._posterQueue.shift()
      if (job) job.cb(code === 0 ? job.file : "")
      notifier.nextPoster()
    }
  }
}
