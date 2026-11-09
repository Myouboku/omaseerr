import QtQuick
import "../model/keymap.js" as KeyMap

// The panel's keys: each page's shortcuts, turned into calls on the panel's
// state (nav) and approval form. Which key does what is decided in
// model/keymap.js; this names the key, describes the focus, and acts.
QtObject {
  // The panel: service, state (nav), approval form, content.
  required property var ctx

  // Qt's keys that type nothing, by the names model/keymap.js uses.
  function keyName(key) {
    switch (key) {
    case Qt.Key_Escape: return "Escape"
    case Qt.Key_Return: return "Return"
    case Qt.Key_Enter: return "Enter"
    case Qt.Key_Up: return "Up"
    case Qt.Key_Down: return "Down"
    case Qt.Key_PageUp: return "PageUp"
    case Qt.Key_PageDown: return "PageDown"
    case Qt.Key_Home: return "Home"
    case Qt.Key_End: return "End"
    case Qt.Key_Backspace: return "Backspace"
    case Qt.Key_Delete: return "Delete"
    }
    return ""
  }

  function handleKey(event) {
    var nav = ctx.nav
    var svc = ctx.svc
    var content = ctx.content
    // The current request only matters on the list and the details.
    var req = !nav.confirmOpen && (nav.page === "list" || nav.page === "detail") ? nav.currentReq() : null
    var a = KeyMap.keyAction({
      key: keyName(event.key),
      text: event.text,
      shift: (event.modifiers & Qt.ShiftModifier) !== 0,
      page: nav.page,
      confirmOpen: nav.confirmOpen,
      inControl: !!content && !content.activeFocus,
      searchFocused: !!content && !!content.searchField && content.searchField.activeFocus,
      searching: !!svc && !!svc.view.search,
      status: req ? req.status : 0
    })
    if (!a) return
    switch (a.action) {
    case "confirm":
      var dialog = content ? content.confirm : null
      if (dialog && dialog.handleKey(event)) event.accepted = true
      return
    case "leaveControl":
      if (a.clearSearch) svc.setView({ search: "" })
      content.forceActiveFocus()
      break
    case "back": nav.back(); break
    case "submit": ctx.approval.submit(a.quick); break
    case "move": if (a.to) nav.moveTo(a.to); else nav.moveCursor(a.by); break
    case "openDetail": nav.openDetail(req); break
    case "approve": nav.approve(req, a.quick); break
    case "decline": nav.decline(req); break
    case "remove": nav.remove(req); break
    case "retry": svc.retry(req.id); break
    case "open": if (svc) svc.openInBrowser(req); break
    case "watch": nav.watch(); break
    case "trailer": nav.trailer(); break
    case "refresh": if (svc) svc.refresh(); break
    case "settings": nav.go("settings"); break
    case "focusSearch": if (content && content.searchField) content.searchField.forceActiveFocus(); break
    case "cycle": nav.cycleView(a.key, a.values, a.backwards); break
    default: return
    }
    event.accepted = true
  }
}
