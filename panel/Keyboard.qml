import QtQuick
import "../model/Seerr.js" as Seerr

// The panel's keys: each page's shortcuts, turned into calls on the panel's
// state (nav) and approval form.
QtObject {
  // The panel: service, state (nav), approval form, content.
  required property var ctx

  function handleKey(event) {
    var nav = ctx.nav
    var svc = ctx.svc
    var page = nav.page
    if (nav.confirmOpen) {
      var dialog = ctx.content ? ctx.content.confirm : null
      if (dialog && dialog.handleKey(event)) event.accepted = true
      return
    }
    var shift = (event.modifiers & Qt.ShiftModifier) !== 0
    var key = event.key
    var text = event.text

    if (key === Qt.Key_Escape) {
      var content = ctx.content
      // On the list and the approval form, Escape first leaves a control
      // (search, a dropdown, a chip, a button) for the page's own keys;
      // the next one goes back.
      if (content && !content.activeFocus && (page === "list" || page === "approve")) {
        if (page === "list" && content.searchField && content.searchField.activeFocus && svc && svc.view.search)
          svc.setView({ search: "" })
        content.forceActiveFocus()
      } else nav.back()
      event.accepted = true
      return
    }
    // Typing goes to text fields; only Escape above reaches us from them.
    if (page === "settings" || page === "approve") {
      if (page === "approve" && (key === Qt.Key_Return || key === Qt.Key_Enter)) {
        ctx.approval.submit(shift)
        event.accepted = true
      }
      return
    }

    var focusedContent = ctx.content
    if (key === Qt.Key_Down && focusedContent && focusedContent.searchField && focusedContent.searchField.activeFocus) {
      focusedContent.forceActiveFocus()
      event.accepted = true
      return
    }
    if (key === Qt.Key_Down || text === "j") { nav.moveCursor(1); event.accepted = true; return }
    if (key === Qt.Key_Up || text === "k") { nav.moveCursor(-1); event.accepted = true; return }
    if (key === Qt.Key_PageDown) { nav.moveCursor(8); event.accepted = true; return }
    if (key === Qt.Key_PageUp) { nav.moveCursor(-8); event.accepted = true; return }
    if (key === Qt.Key_Home) { nav.moveCursor(-nav.visibleRows.length); event.accepted = true; return }
    if (key === Qt.Key_End) { nav.moveCursor(nav.visibleRows.length); event.accepted = true; return }
    if (key === Qt.Key_Backspace || text === "h") {
      if (page === "detail") { nav.back(); event.accepted = true }
      return
    }

    var req = nav.currentReq()
    if (key === Qt.Key_Return || key === Qt.Key_Enter) {
      if (page === "list" && !shift) nav.openDetail(req)
      else nav.approve(req, shift)
      event.accepted = true
      return
    }
    if (text === "a") { nav.approve(req, false); event.accepted = true; return }
    if (text === "A") { nav.approve(req, true); event.accepted = true; return }
    if (text === "d" || text === "D") { nav.decline(req); event.accepted = true; return }
    if (key === Qt.Key_Delete || text === "x") { nav.remove(req); event.accepted = true; return }
    if (text === "R" && req && req.status === Seerr.REQUEST_FAILED) { svc.retry(req.id); event.accepted = true; return }
    if (text === "o") { if (svc) svc.openInBrowser(req); event.accepted = true; return }
    if (text === "r") { if (svc) svc.refresh(); event.accepted = true; return }
    if (text === "s") { nav.go("settings"); event.accepted = true; return }
    if (page === "list") {
      if (text === "/") {
        var c = ctx.content
        if (c && c.searchField) c.searchField.forceActiveFocus()
        event.accepted = true
        return
      }
      if (text === "f" || text === "F") { nav.cycleView("filter", Seerr.FILTERS, text === "F"); event.accepted = true; return }
      if (text === "t") { nav.cycleView("mediaType", Seerr.MEDIA_TYPES, shift); event.accepted = true; return }
      if (text === "S") { nav.cycleView("sort", Seerr.SORTS, false); event.accepted = true; return }
      if (text === "i") { nav.cycleView("sortDirection", Seerr.DIRECTIONS, false); event.accepted = true; return }
    }
  }
}
