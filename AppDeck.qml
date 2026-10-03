import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "AppDeckModel.js" as AppDeckModel

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  readonly property var allApps: selection.allApps
  readonly property var apps: selection.apps
  readonly property string searchQuery: selection.searchQuery
  property alias selectedIdentity: selection.selectedIdentity
  readonly property string selectedWindowId: selection.selectedWindowId
  property string footerMessage: ""
  readonly property var pendingFocusHandle: focusController.pendingFocusHandle
  property string pendingLaunchIdentity: ""
  readonly property var pendingForceKillApp: killController.pendingForceKillApp
  readonly property var forceKillRequests: killController.forceKillRequests

  property var desktop: nativeDesktop.item
  Loader {
    id: nativeDesktop
    active: !root.desktop || root.desktop === item
    source: "AppDeckDesktop.qml"
  }
  Connections {
    target: root.desktop
    function onChanged() { root.scheduleRebuild() }
  }
  AppDeckSelection {
    id: selection
    entries: root.desktopEntries()
    onResultsChanged: root.revealSelected()
    onWindowChosen: root.revealSelectedWindow()
    onWindowUnavailable: {
      if (root.pendingFocusHandle) {
        root.opened = true
        root.restoreListFocus()
      }
      root.clearPendingFocus()
      root.footerMessage = "Selected window is no longer available. Select again."
    }
  }
  AppDeckFocus {
    id: focusController
    desktop: root.desktop
    selection: selection
    onStarted: root.opened = false
    onSucceeded: root.dismiss()
    onFailed: root.reportFocusError()
  }

  AppDeckKill {
    id: killController
    desktop: root.desktop
    selection: selection
    refresh: function() { root.rebuild() }
    onMessageChanged: root.footerMessage = message
    onSettled: root.restoreListFocus()
  }

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  readonly property int cornerRadius: Style.cornerRadius
  readonly property string fontFamily: Style.font.menuFamily
  readonly property int rowHeight: Style.space(64)
  readonly property var appLibrary: root.shell ? root.shell.appLibrary : null
  readonly property bool hasSearchQuery: root.searchQuery.trim().length > 0
  readonly property int selectedIndex: selection.selectedIndex
  readonly property var selectedApp: selection.selectedApp
  readonly property bool windowSelectionActive: selection.windowSelectionActive
  readonly property var selectedWindow: selection.selectedWindow
  readonly property int totalWindows: {
    var total = 0
    for (var i = 0; i < allApps.length; i++) total += allApps[i].windowCount
    return total
  }

  function iconSource(icon) {
    if (root.appLibrary && typeof root.appLibrary.iconSource === "function")
      return root.appLibrary.iconSource(icon)
    var value = String(icon || "")
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    var source = Quickshell.iconPath(value || "application-x-executable", true)
    return source || Quickshell.iconPath("application-x-executable", true)
  }

  function desktopEntries() {
    if (root.appLibrary && typeof root.appLibrary.sortedEntries === "function") {
      var rows = root.appLibrary.sortedEntries("")
      return rows.map(function(row) { return row.entry })
    }
    return DesktopEntries.applications.values || []
  }

  function desktopEntry(entryId) {
    var normalizedId = AppDeckModel.normalizedDesktopEntryId(entryId)
    var entries = root.desktopEntries()
    for (var i = 0; i < entries.length; i++) {
      if (AppDeckModel.normalizedDesktopEntryId(entries[i].id) === normalizedId)
        return entries[i]
    }
    return null
  }

  function clearWindowSelection() {
    return selection.clearWindowSelection()
  }

  function chooseWindow(id) { selection.chooseWindow(id) }

  function selectWindow(delta) {
    root.clearPendingFocus()
    root.footerMessage = ""
    selection.selectWindow(delta)
  }

  function revealSelectedWindow() {
    Qt.callLater(function() {
      if (!root.windowSelectionActive || !root.selectedApp) return
      for (var i = 0; i < root.selectedApp.windows.length; i++) {
        if (root.selectedApp.windows[i].id === root.selectedWindowId) {
          view.revealWindow(i)
          return
        }
      }
    })
  }

  function rebuild() {
    selection.rebuild(desktop.snapshots(), function(appId) {
      return desktop.lookupApp(appId)
    })
  }

  function scheduleRebuild() {
    rebuildTimer.restart()
  }

  function handleKey(event) {
    // Fcitx can leave a cursor attribute after cancelling an empty preedit.
    if (view.composing) return

    if (root.pendingForceKillApp) {
      if (view.handleConfirmation(event)) event.accepted = true
      return
    }

    if (event.key === Qt.Key_Escape) {
      if (root.searchQuery) root.setSearchQuery("")
      else root.dismiss()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.activateSelectedApp()
      event.accepted = true
    } else if ((event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)
        && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
      root.selectWindow(event.key === Qt.Key_Backtab || event.modifiers & Qt.ShiftModifier ? -1 : 1)
      event.accepted = true
    } else if (event.key === Qt.Key_Delete) {
      if (root.windowSelectionActive) {
        event.accepted = true
        return
      }
      if (event.modifiers & Qt.ShiftModifier)
        root.requestForceKill()
      else if (event.modifiers === Qt.NoModifier)
        root.requestGracefulClose()
      event.accepted = true
    } else if (event.key === Qt.Key_U && event.modifiers === Qt.ControlModifier) {
      root.setSearchQuery("")
      event.accepted = true
    } else if (event.key === Qt.Key_Up) {
      root.select(-1)
      event.accepted = true
    } else if (event.key === Qt.Key_Down) {
      root.select(1)
      event.accepted = true
    } else if (event.key === Qt.Key_PageUp) {
      root.selectPage(-1)
      event.accepted = true
    } else if (event.key === Qt.Key_PageDown) {
      root.selectPage(1)
      event.accepted = true
    } else if (event.key === Qt.Key_Home) {
      root.selectAbsolute(0)
      event.accepted = true
    } else if (event.key === Qt.Key_End) {
      root.selectAbsolute(root.apps.length - 1)
      event.accepted = true
    }
  }

  onOpenedChanged: {
    if (!root.opened) view.resetComposition()
  }

  function open(payloadJson) {
    root.clearWindowSelection()
    root.clearPendingFocus()
    root.pendingLaunchIdentity = ""
    root.clearForceKillConfirmation()
    root.setSearchQuery("")
    root.footerMessage = ""
    root.rebuild()
    root.selectedIdentity = AppDeckModel.initialSelectedIdentity(root.apps)
    root.opened = true
    Qt.callLater(function() {
      view.focusInput()
      root.revealSelected()
    })
  }

  function setSearchQuery(query) {
    root.clearPendingFocus()
    view.setInputText(query)
    selection.search(query)
  }

  function select(delta) {
    root.clearPendingFocus()
    selection.select(delta)
  }

  function selectAbsolute(index) {
    root.clearPendingFocus()
    selection.selectAbsolute(index)
  }

  function selectPage(direction) {
    root.selectAbsolute(AppDeckModel.pageSelectionIndex(
      root.selectedIndex, root.apps.length, view.pageSize, direction))
  }

  function revealSelected() {
    Qt.callLater(function() {
      if (root.selectedIndex >= 0)
        view.revealApp(root.selectedIndex)
    })
  }

  function focusSelectedApp() {
    if (root.windowSelectionActive) root.focusWindow(root.selectedWindow)
    else root.focusApp(root.selectedApp)
  }

  function focusApp(app) {
    root.focusWindow(AppDeckModel.mostRecentlyActiveAppWindow(app))
  }

  function focusWindow(target) {
    root.footerMessage = ""
    focusController.request(target)
  }

  function activateSelectedApp() {
    if (!root.selectedApp) return
    if (root.selectedApp && root.selectedApp.kind === "launch")
      root.launchSelectedApp()
    else
      root.focusSelectedApp()
  }

  function launchSelectedApp() {
    root.clearPendingFocus()
    root.footerMessage = ""
    var selected = root.selectedApp
    if (!selected || selected.kind !== "launch" || root.pendingLaunchIdentity) return

    var entryId = selected.desktopEntryId
    root.rebuild()
    var runningApp = AppDeckModel.runningAppForDesktopEntry(root.allApps, entryId)
    if (runningApp) {
      root.selectedIdentity = runningApp.identity
      root.focusApp(runningApp)
      return
    }

    var entry = root.desktopEntry(entryId)
    if (!entry) {
      root.footerMessage = "This app is no longer available."
      root.restoreListFocus()
      return
    }

    root.pendingLaunchIdentity = "launch:" + AppDeckModel.normalizedDesktopEntryId(entryId)
    root.opened = false
    Qt.callLater(function() {
      if (!root.pendingLaunchIdentity) return
      try {
        if (root.appLibrary && typeof root.appLibrary.launch === "function")
          root.appLibrary.launch(entry.id, entry.name)
        else if (typeof entry.execute === "function")
          entry.execute()
        else
          throw new Error("No desktop application launcher is available")
        root.pendingLaunchIdentity = ""
        root.dismiss()
      } catch (error) {
        root.pendingLaunchIdentity = ""
        root.opened = true
        root.footerMessage = "Unable to start this app."
        root.restoreListFocus()
      }
    })
  }

  function requestGracefulClose() {
    root.clearPendingFocus()
    root.footerMessage = ""
    if (!root.selectedApp || root.selectedApp.kind !== "running") return
    var targets = AppDeckModel.gracefulCloseTargets(root.selectedApp)
    var failures = 0

    for (var i = 0; i < targets.length; i++) {
      var handle = targets[i].handle
      if (!handle || typeof handle.close !== "function") {
        failures++
        continue
      }
      try {
        handle.close()
      } catch (error) {
        failures++
      }
    }

    if (!targets.length || failures === targets.length)
      root.footerMessage = "Unable to send Close Request."
    else if (failures)
      root.footerMessage = "Some Close Requests could not be sent."
    else
      root.footerMessage = "Close Request sent to " + targets.length
        + (targets.length === 1 ? " window." : " windows.")
  }

  function requestForceKill() {
    root.clearPendingFocus()
    root.footerMessage = ""
    killController.requestForceKill()
    if (root.pendingForceKillApp) view.beginConfirmation()
    root.restoreListFocus()
  }

  function completeForceKill(confirmed) {
    root.footerMessage = ""
    killController.completeForceKill(confirmed)
    root.restoreListFocus()
  }

  function clearPendingFocus() { focusController.cancel() }

  function clearForceKillConfirmation() {
    killController.cancelReview()
  }

  function restoreListFocus() {
    if (root.opened)
      Qt.callLater(function() {
        if (!root.opened) return
        view.focusControls()
      })
  }

  function reportFocusError() {
    root.clearPendingFocus()
    root.opened = true
    root.footerMessage = root.windowSelectionActive
      ? "Unable to focus this window." : "Unable to focus this app."
    root.restoreListFocus()
  }

  function close() {
    root.clearWindowSelection()
    root.clearPendingFocus()
    root.pendingLaunchIdentity = ""
    root.clearForceKillConfirmation()
    root.opened = false
  }

  function dismiss() {
    root.clearWindowSelection()
    root.clearPendingFocus()
    root.pendingLaunchIdentity = ""
    root.clearForceKillConfirmation()
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "appdeck.app")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  Timer {
    id: rebuildTimer
    interval: 0
    onTriggered: root.rebuild()
  }

  Connections {
    target: root.appLibrary
    function onAppsChanged() { root.scheduleRebuild() }
  }

  Component.onCompleted: {
    desktop.refresh()
    root.rebuild()
  }

  AppDeckView {
    id: view
    controller: root
  }
}
