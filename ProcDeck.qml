import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "ProcDeckModel.js" as ProcDeckModel

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property var allApps: []
  property var apps: []
  property var activityOrderIdentities: []
  property string searchQuery: ""
  property string selectedIdentity: ""
  property string footerMessage: ""
  property var pendingFocusHandle: null
  property string pendingLaunchIdentity: ""
  property var pendingForceKillApp: null
  property var forceKillRequests: []
  property int forceKillResponseCount: 0
  property int forceKillFailureCount: 0

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
  readonly property bool compactActions: card.width < Style.space(640)
  readonly property var appLibrary: root.shell ? root.shell.appLibrary : null
  readonly property bool hasSearchQuery: root.searchQuery.trim().length > 0
  readonly property int selectedIndex: {
    for (var i = 0; i < apps.length; i++)
      if (apps[i].identity === selectedIdentity) return i
    return -1
  }
  readonly property var selectedApp: selectedIndex >= 0 && selectedIndex < apps.length
    ? apps[selectedIndex] : null
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

  function snapshots() {
    var values = Hyprland.toplevels.values || []
    var out = []
    var seenAddresses = ({})

    for (var i = 0; i < values.length; i++) {
      var hyprlandToplevel = values[i]
      var waylandToplevel = hyprlandToplevel.wayland
      var address = ProcDeckModel.normalizedHyprlandAddress(
        hyprlandToplevel.address)
      if (!waylandToplevel || !address || seenAddresses[address]) continue
      seenAddresses[address] = true

      var ipc = hyprlandToplevel.lastIpcObject || {}
      var workspace = hyprlandToplevel.workspace
      var workspaceId = workspace ? workspace.id : ""
      var workspaceName = workspace ? String(workspace.name || "").trim() : ""

      out.push({
        id: address || String(i),
        handle: waylandToplevel,
        parent: waylandToplevel ? waylandToplevel.parent : null,
        ownerIdentity: ipc.pid,
        hyprlandAddress: address,
        appId: String((waylandToplevel && waylandToplevel.appId) || ""),
        title: String((waylandToplevel && waylandToplevel.title) || hyprlandToplevel.title || ipc.title || ""),
        workspace: workspaceName || (workspaceId ? String(workspaceId) : ""),
        focusHistoryId: ipc.focusHistoryID,
        activated: hyprlandToplevel.activated === true
          || (waylandToplevel && waylandToplevel.activated === true)
      })
    }

    return out
  }

  function desktopEntries() {
    if (root.appLibrary && typeof root.appLibrary.sortedEntries === "function") {
      var rows = root.appLibrary.sortedEntries("")
      return rows.map(function(row) { return row.entry })
    }
    return DesktopEntries.applications.values || []
  }

  function desktopEntry(entryId) {
    var normalizedId = ProcDeckModel.normalizedDesktopEntryId(entryId)
    var entries = root.desktopEntries()
    for (var i = 0; i < entries.length; i++) {
      if (ProcDeckModel.normalizedDesktopEntryId(entries[i].id) === normalizedId)
        return entries[i]
    }
    return null
  }

  function updateSearchResults(previousSelection, previousIndex, preserveSelection) {
    root.apps = ProcDeckModel.searchResults(
      root.allApps, root.desktopEntries(), root.searchQuery)
    root.selectedIdentity = preserveSelection
      ? ProcDeckModel.reconcileSelectedIdentity(previousSelection, previousIndex, root.apps)
      : root.apps.length ? root.apps[0].identity : ""
    root.revealSelected()
  }

  function rebuild() {
    var previousSelection = root.selectedApp
    var previousIndex = root.selectedIndex
    var groupedApps = ProcDeckModel.runningApps(root.snapshots(), function(appId) {
      return DesktopEntries.heuristicLookup(appId)
    })
    var nextApps = ProcDeckModel.orderRunningApps(groupedApps, root.activityOrderIdentities)

    root.activityOrderIdentities = nextApps.map(function(app) { return app.identity })
    root.allApps = nextApps
    root.updateSearchResults(previousSelection, previousIndex, true)
  }

  function scheduleRebuild() {
    rebuildTimer.restart()
  }

  function open(payloadJson) {
    root.clearPendingFocus()
    root.pendingLaunchIdentity = ""
    root.clearForceKillConfirmation()
    root.searchQuery = ""
    root.footerMessage = ""
    root.rebuild()
    root.selectedIdentity = ProcDeckModel.initialSelectedIdentity(root.apps)
    root.opened = true
    Qt.callLater(function() {
      keyCatcher.forceActiveFocus()
      root.revealSelected()
    })
  }

  function setSearchQuery(query) {
    root.clearPendingFocus()
    root.searchQuery = query
    root.updateSearchResults(null, 0, false)
  }

  function select(delta) {
    root.clearPendingFocus()
    if (!root.apps.length) return
    var index = root.selectedIndex
    if (index < 0) index = delta < 0 ? root.apps.length - 1 : 0
    else index = ((index + delta) % root.apps.length + root.apps.length) % root.apps.length
    root.selectedIdentity = root.apps[index].identity
    root.revealSelected()
  }

  function selectAbsolute(index) {
    root.clearPendingFocus()
    if (!root.apps.length) return
    index = Math.max(0, Math.min(index, root.apps.length - 1))
    root.selectedIdentity = root.apps[index].identity
    root.revealSelected()
  }

  function selectPage(direction) {
    var rowExtent = root.rowHeight + appList.spacing
    var pageSize = Math.max(1, Math.floor((appList.height + appList.spacing) / rowExtent))
    root.selectAbsolute(ProcDeckModel.pageSelectionIndex(
      root.selectedIndex, root.apps.length, pageSize, direction))
  }

  function revealSelected() {
    Qt.callLater(function() {
      if (root.selectedIndex >= 0)
        appList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function focusSelectedApp() {
    root.focusApp(root.selectedApp)
  }

  function focusApp(app) {
    root.clearPendingFocus()
    root.footerMessage = ""
    var target = ProcDeckModel.mostRecentlyActiveAppWindow(app)
    var command = ProcDeckModel.focusCommand(target)
    if (!target || !target.handle || !command) {
      root.reportFocusError()
      return
    }

    root.pendingFocusHandle = target.handle
    root.opened = false
    Qt.callLater(function() {
      if (!root.pendingFocusHandle) return
      focusAcknowledgementTimer.restart()
      try {
        Hyprland.dispatch(command)
        if (root.pendingFocusHandle
            && root.pendingFocusHandle.activated === true)
          root.dismiss()
      } catch (error) {
        root.reportFocusError()
      }
    })
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
    var runningApp = ProcDeckModel.runningAppForDesktopEntry(root.allApps, entryId)
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

    root.pendingLaunchIdentity = "launch:" + ProcDeckModel.normalizedDesktopEntryId(entryId)
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
    var targets = ProcDeckModel.gracefulCloseTargets(root.selectedApp)
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
    if (root.forceKillRequests.length) {
      root.footerMessage = "A Kill request is still pending."
      return
    }
    if (!root.selectedApp || root.selectedApp.kind !== "running") {
      root.footerMessage = "Unable to request Kill."
      return
    }

    root.pendingForceKillApp = {
      identity: root.selectedApp.identity,
      name: root.selectedApp.name,
      windowCount: root.selectedApp.windows.length,
      forceKillScope: ProcDeckModel.forceKillScope(root.selectedApp)
    }
    forceKillConfirm.selectedIndex = 1
    root.restoreListFocus()
  }

  function completeForceKill(confirmed) {
    var pendingApp = root.pendingForceKillApp
    root.pendingForceKillApp = null
    root.footerMessage = ""
    var currentApp = null
    if (confirmed && pendingApp) {
      root.rebuild()
      for (var i = 0; i < root.allApps.length; i++) {
        if (root.allApps[i].identity === pendingApp.identity) {
          currentApp = root.allApps[i]
          break
        }
      }
    }
    var targets = ProcDeckModel.forceKillTargets(
      currentApp || pendingApp, confirmed, root.allApps)
    if (!confirmed) {
      root.restoreListFocus()
      return
    }
    if (!currentApp || currentApp.windowCount !== pendingApp.windowCount
        || !ProcDeckModel.forceKillScopeMatches(
          currentApp, pendingApp.forceKillScope)) {
      root.footerMessage = "Kill target changed. Review it again."
      root.restoreListFocus()
      return
    }
    if (!ProcDeckModel.forceKillScopeIsExclusive(currentApp, root.allApps)) {
      root.footerMessage = "Kill target is shared with another Running App."
      root.restoreListFocus()
      return
    }
    if (!targets.length)
      root.footerMessage = "No valid Kill targets."
    else if (!Hyprland.requestSocketPath)
      root.footerMessage = "Unable to send Kill request."
    else {
      root.forceKillResponseCount = 0
      root.forceKillFailureCount = 0
      root.forceKillRequests = targets
    }
    root.restoreListFocus()
  }

  function recordForceKillResponse(succeeded) {
    if (!root.forceKillRequests.length) return
    root.forceKillResponseCount++
    if (!succeeded) root.forceKillFailureCount++
    if (root.forceKillResponseCount < root.forceKillRequests.length) return

    var requestCount = root.forceKillRequests.length
    var failures = root.forceKillFailureCount
    root.forceKillRequests = []
    if (failures === requestCount)
      root.footerMessage = "Unable to send Kill request."
    else if (failures)
      root.footerMessage = "Some Kill requests could not be sent."
    else
      root.footerMessage = "Kill requested for " + requestCount
        + (requestCount === 1 ? " owner." : " owners.")
    root.restoreListFocus()
  }

  function clearPendingFocus() {
    focusAcknowledgementTimer.stop()
    root.pendingFocusHandle = null
  }

  function clearForceKillConfirmation() {
    root.pendingForceKillApp = null
  }

  function restoreListFocus() {
    if (root.opened)
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function reportFocusError() {
    root.clearPendingFocus()
    root.opened = true
    root.footerMessage = "Unable to focus this app."
    root.restoreListFocus()
  }

  function close() {
    root.clearPendingFocus()
    root.pendingLaunchIdentity = ""
    root.clearForceKillConfirmation()
    root.opened = false
  }

  function dismiss() {
    root.clearPendingFocus()
    root.pendingLaunchIdentity = ""
    root.clearForceKillConfirmation()
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "procdeck.app")
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

  Timer {
    id: focusAcknowledgementTimer
    interval: 250
    repeat: false
    onTriggered: root.reportFocusError()
  }

  Connections {
    target: Hyprland.toplevels
    function onValuesChanged() { root.scheduleRebuild() }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event ? String(event.name) : ""
      if (name === "activewindow" || name === "activewindowv2")
        Hyprland.refreshToplevels()
      root.scheduleRebuild()
    }
  }

  Instantiator {
    model: Hyprland.toplevels.values || []
    delegate: Connections {
      required property var modelData
      target: modelData
      function onLastIpcObjectChanged() { root.scheduleRebuild() }
      function onWaylandHandleChanged() { root.scheduleRebuild() }
    }
  }

  Instantiator {
    model: root.forceKillRequests
    delegate: Socket {
      id: forceKillSocket
      required property string modelData
      property bool finished: false
      property bool requestWritten: false
      property string responseBuffer: ""
      property Timer responseTimeout: Timer {
        interval: 1500
        running: !forceKillSocket.finished
        repeat: false
        onTriggered: forceKillSocket.acceptResponse("", true)
      }

      path: Hyprland.requestSocketPath
      connected: !finished

      function acceptResponse(chunk, ended) {
        if (finished) return
        var state = ProcDeckModel.forceKillResponseState(
          responseBuffer, chunk, ended)
        responseBuffer = state.response
        if (state.done) finish(state.succeeded)
      }

      function finish(succeeded) {
        if (finished) return
        finished = true
        root.recordForceKillResponse(succeeded)
      }

      onConnectionStateChanged: {
        if (finished) return
        if (connected) {
          requestWritten = true
          write("dispatch " + modelData)
          flush()
        } else if (requestWritten) {
          acceptResponse("", true)
        }
      }
      onError: function(error) { forceKillSocket.acceptResponse("", true) }

      parser: SplitParser {
        splitMarker: ""
        onRead: function(response) {
          forceKillSocket.acceptResponse(response, false)
        }
      }
    }
  }

  Connections {
    target: root.pendingFocusHandle
    function onActivatedChanged() {
      if (root.pendingFocusHandle
          && root.pendingFocusHandle.activated === true)
        root.dismiss()
    }
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() { root.scheduleRebuild() }
  }

  Connections {
    target: root.appLibrary
    function onAppsChanged() { root.scheduleRebuild() }
  }

  Component.onCompleted: {
    Hyprland.refreshToplevels()
    root.rebuild()
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; right: true; bottom: true; left: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "procdeck"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened
      ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: Math.min(Style.space(980), panel.width - Style.gapsOut * 2)
      height: Math.min(Style.space(660), panel.height - Style.gapsOut * 2)
      anchors.centerIn: parent
      radius: root.cornerRadius
      color: root.background
      borderSpec: root.borderSpec
      padding: Style.spacing.panelPadding

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        z: root.pendingForceKillApp ? 20 : 0
        focus: root.opened

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.pendingForceKillApp) {
            if (forceKillConfirm.handleKey(event)) event.accepted = true
            return
          }

          if (event.key === Qt.Key_Escape) {
            if (root.searchQuery) root.setSearchQuery("")
            else root.dismiss()
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.activateSelectedApp()
            event.accepted = true
          } else if (event.key === Qt.Key_Delete) {
            if (event.modifiers & Qt.ShiftModifier)
              root.requestForceKill()
            else if (event.modifiers === Qt.NoModifier)
              root.requestGracefulClose()
            event.accepted = true
          } else if (Util.editsFilter(event, root.searchQuery)) {
            root.setSearchQuery(Util.editedFilter(event, root.searchQuery))
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
          } else if (event.text && event.text.length === 1
                     && event.text.charCodeAt(0) >= 32
                     && event.text.charCodeAt(0) !== 127
                     && (event.modifiers === Qt.NoModifier
                         || event.modifiers === Qt.ShiftModifier)) {
            root.setSearchQuery(root.searchQuery + event.text)
            event.accepted = true
          }
        }

        ConfirmDialog {
          id: forceKillConfirm

          anchors.fill: parent
          opened: root.pendingForceKillApp !== null
          z: 10
          message: root.pendingForceKillApp
            ? "Kill “" + root.pendingForceKillApp.name + "” and its "
              + root.pendingForceKillApp.windowCount
              + (root.pendingForceKillApp.windowCount === 1
                ? " App Window?" : " App Windows?")
              + " Unsaved work may be lost."
            : ""
          confirmText: "Kill"
          background: root.background
          foreground: root.foreground
          scrim: root.scrim
          selectedBackground: root.selectedBackground
          selectedText: root.selectedText
          fontFamily: root.fontFamily
          cornerRadius: root.cornerRadius
          onCanceled: root.completeForceKill(false)
          onConfirmed: root.completeForceKill(true)
        }
      }

      ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.spacing.panelGap

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.controlGap

          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.spacing.xs

            Text {
              text: "Apps"
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.weight: Font.DemiBold
            }

            Text {
              Layout.fillWidth: true
              text: root.hasSearchQuery ? root.searchQuery : "Type to search…"
              textFormat: Text.PlainText
              color: root.foreground
              opacity: root.hasSearchQuery ? 1 : 0.58
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }
          }

          Text {
            text: root.apps.length
              + (root.hasSearchQuery ? " matches" : " apps")
              + " · " + root.allApps.length + " running"
              + " · " + root.totalWindows
              + (root.totalWindows === 1 ? " window" : " windows")
            textFormat: Text.PlainText
            color: root.foreground
            opacity: 0.58
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Rectangle {
          Layout.fillWidth: true
          height: Style.spacing.hairline
          color: Util.alpha(root.foreground, 0.16)
        }

        ColumnLayout {
          id: contentLayout
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: Style.spacing.panelGap

          Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
              id: appList
              anchors.fill: parent
              clip: true
              spacing: Style.spacing.sm
              model: root.apps

              delegate: BorderSurface {
                id: appRow
                required property int index
                required property var modelData

                readonly property bool selected: index === root.selectedIndex
                width: ListView.view.width
                height: root.rowHeight
                radius: root.cornerRadius
                color: selected ? root.selectedBackground : "transparent"
                borderSpec: selected
                  ? Border.controlSpec("selected", root.foreground, Color.accent)
                  : Border.none()

                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: Style.spacing.rowPaddingX
                  anchors.rightMargin: Style.spacing.rowPaddingX
                  spacing: Style.spacing.controlGap

                  Image {
                    Layout.preferredWidth: Style.font.iconLarge
                    Layout.preferredHeight: Style.font.iconLarge
                    sourceSize.width: width * Screen.devicePixelRatio
                    sourceSize.height: height * Screen.devicePixelRatio
                    source: root.iconSource(appRow.modelData.icon)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                  }

                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.spacing.xs

                    Text {
                      Layout.fillWidth: true
                      text: appRow.modelData.name
                      textFormat: Text.PlainText
                      color: appRow.selected ? root.selectedText : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.weight: Font.Medium
                      elide: Text.ElideRight
                    }

                    Text {
                      Layout.fillWidth: true
                      text: appRow.modelData.kind === "launch"
                        ? "Not running · " + appRow.modelData.desktopEntryId + " · Start Running"
                        : appRow.modelData.windowCount
                          + (appRow.modelData.windowCount === 1 ? " window" : " windows")
                          + (appRow.modelData.workspaces.length
                            ? " · Workspace " + appRow.modelData.workspaces.join(", ") : "")
                      textFormat: Text.PlainText
                      color: appRow.selected ? root.selectedText : root.foreground
                      opacity: 0.58
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.selectAbsolute(appRow.index)
                    root.activateSelectedApp()
                  }
                }
              }

              Text {
                visible: root.apps.length === 0
                anchors.centerIn: parent
                width: parent.width - Style.spacing.panelPadding * 2
                text: root.hasSearchQuery
                  ? "No matching apps"
                  : "No Apps"
                textFormat: Text.PlainText
                horizontalAlignment: Text.AlignHCenter
                color: root.foreground
                opacity: 0.58
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }
          }

          BorderSurface {
            id: detailCard
            Layout.fillWidth: true
            Layout.preferredHeight: detailContent.implicitHeight
              + detailCard.contentTopInset + detailCard.contentBottomInset
            Layout.minimumHeight: Layout.preferredHeight
            radius: root.cornerRadius
            color: Style.normalFill
            borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
            padding: Style.spacing.panelPadding

            ColumnLayout {
              id: detailContent
              anchors.fill: parent
              anchors.topMargin: parent.contentTopInset
              anchors.rightMargin: parent.contentRightInset
              anchors.bottomMargin: parent.contentBottomInset
              anchors.leftMargin: parent.contentLeftInset
              spacing: Style.spacing.md

              RowLayout {
                Layout.fillWidth: true
                spacing: Style.spacing.controlGap

                BorderSurface {
                  Layout.preferredWidth: Style.space(42)
                  Layout.preferredHeight: Style.space(42)
                  radius: root.cornerRadius
                  color: root.background
                  borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

                  Image {
                    anchors.centerIn: parent
                    width: Style.font.iconLarge
                    height: Style.font.iconLarge
                    sourceSize.width: width * Screen.devicePixelRatio
                    sourceSize.height: height * Screen.devicePixelRatio
                    source: root.iconSource(root.selectedApp ? root.selectedApp.icon : "")
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                  }
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.spacing.xs

                  RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.spacing.controlGap

                    Text {
                      text: root.selectedApp ? root.selectedApp.name : "No selection"
                      textFormat: Text.PlainText
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.heading
                      font.weight: Font.DemiBold
                      elide: Text.ElideRight
                    }

                    Text {
                      Layout.fillWidth: true
                      text: root.selectedApp && root.selectedApp.kind === "launch"
                        ? root.selectedApp.desktopEntryId
                        : root.selectedApp && root.selectedApp.appId
                          ? root.selectedApp.appId : "Unidentified App"
                      textFormat: Text.PlainText
                      color: root.foreground
                      opacity: 0.5
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideMiddle
                    }
                  }

                  Text {
                    Layout.fillWidth: true
                    text: root.selectedApp && root.selectedApp.kind === "launch"
                      ? "Not running · Ready to start"
                      : root.selectedApp
                      ? root.selectedApp.windowCount
                        + (root.selectedApp.windowCount === 1 ? " window" : " windows")
                        + (root.selectedApp.workspaces.length
                          ? " · Workspace " + root.selectedApp.workspaces.join(", ") : "")
                      : "No App Windows"
                    textFormat: Text.PlainText
                    color: root.foreground
                    opacity: 0.58
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }
              }

              Text {
                Layout.fillWidth: true
                text: root.selectedApp && root.selectedApp.kind === "launch"
                  ? "Installed application"
                  : root.selectedApp && root.selectedApp.currentTitle
                    ? root.selectedApp.currentTitle : "No window title"
                textFormat: Text.PlainText
                color: root.foreground
                opacity: 0.78
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
              }

              Rectangle {
                Layout.fillWidth: true
                height: Style.spacing.hairline
                color: Util.alpha(root.foreground, 0.16)
              }

              GridLayout {
                Layout.fillWidth: true
                columns: root.compactActions ? 1 : 2
                columnSpacing: Style.spacing.controlGap
                rowSpacing: Style.spacing.sm

                Text {
                  Layout.fillWidth: true
                  text: root.selectedApp && root.selectedApp.kind === "launch"
                    ? "Start this installed application"
                    : "Close / Kill · all App Windows"
                  textFormat: Text.PlainText
                  color: root.foreground
                  opacity: 0.58
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }

                RowLayout {
                  Layout.fillWidth: root.compactActions
                  Layout.alignment: Qt.AlignRight
                  spacing: Style.spacing.sm

                  Button {
                    Layout.fillWidth: root.compactActions
                    text: root.selectedApp && root.selectedApp.kind === "launch"
                      ? "Start Running  ↵" : "Focus  ↵"
                    bordered: true
                    enabled: root.selectedApp !== null && !root.pendingLaunchIdentity
                    opacity: enabled ? 1 : 0.5
                    background: root.selectedBackground
                    foreground: root.selectedText
                    fontFamily: root.fontFamily
                    onClicked: root.activateSelectedApp()
                  }

                  Button {
                    visible: root.selectedApp !== null
                      && root.selectedApp.kind === "running"
                    Layout.fillWidth: root.compactActions
                    text: "Close  Del"
                    bordered: true
                    enabled: root.selectedApp !== null
                      && root.selectedApp.kind === "running"
                    opacity: enabled ? 1 : 0.5
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    onClicked: root.requestGracefulClose()
                  }

                  Button {
                    visible: root.selectedApp !== null
                      && root.selectedApp.kind === "running"
                    Layout.fillWidth: root.compactActions
                    text: "Kill  ⇧Del"
                    bordered: true
                    enabled: root.selectedApp !== null
                      && root.selectedApp.kind === "running"
                      && !root.forceKillRequests.length
                    opacity: enabled ? 1 : 0.5
                    foreground: Color.urgent
                    fontFamily: root.fontFamily
                    onClicked: root.requestForceKill()
                  }
                }
              }
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.controlGap

          Text {
            visible: root.footerMessage === ""
            text: "↑↓ Select · Enter "
              + (root.selectedApp && root.selectedApp.kind === "launch"
                ? "Start Running" : "Focus")
            textFormat: Text.PlainText
            color: root.foreground
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            Layout.fillWidth: true
            visible: root.footerMessage !== ""
            text: root.footerMessage
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignRight
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          Text {
            visible: root.footerMessage === ""
            Layout.fillWidth: true
            text: "Esc Clear / Close"
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignRight
            color: root.foreground
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
