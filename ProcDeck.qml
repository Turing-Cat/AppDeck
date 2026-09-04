import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
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
  property var pendingForceKillApp: null

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
  readonly property bool narrow: card.width < Style.space(760)
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
    var value = String(icon || "")
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    var source = Quickshell.iconPath(value || "application-x-executable", true)
    return source || Quickshell.iconPath("application-x-executable", true)
  }

  function snapshots() {
    var values = Hyprland.toplevels.values || []
    var out = []

    for (var i = 0; i < values.length; i++) {
      var hyprlandToplevel = values[i]
      var waylandToplevel = hyprlandToplevel.wayland
      var ipc = hyprlandToplevel.lastIpcObject || {}
      var address = String(hyprlandToplevel.address || "")
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

  function rebuild() {
    var previousIndex = root.selectedIndex
    var groupedApps = ProcDeckModel.runningApps(root.snapshots(), function(appId) {
      return DesktopEntries.heuristicLookup(appId)
    })
    var nextApps = ProcDeckModel.orderRunningApps(groupedApps, root.activityOrderIdentities)

    root.activityOrderIdentities = nextApps.map(function(app) { return app.identity })
    root.allApps = nextApps
    root.apps = ProcDeckModel.filterRunningApps(nextApps, root.searchQuery)
    root.selectedIdentity = ProcDeckModel.reconcileSelectedIdentity(
      root.selectedIdentity, previousIndex, root.apps)
    root.revealSelected()
  }

  function scheduleRebuild() {
    rebuildTimer.restart()
  }

  function open(payloadJson) {
    root.clearPendingFocus()
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
    var previousIndex = root.selectedIndex
    root.searchQuery = query
    root.apps = ProcDeckModel.filterRunningApps(root.allApps, query)
    root.selectedIdentity = ProcDeckModel.reconcileSelectedIdentity(
      root.selectedIdentity, previousIndex, root.apps)
    root.revealSelected()
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
    root.clearPendingFocus()
    root.footerMessage = ""
    var target = ProcDeckModel.mostRecentlyActiveAppWindow(root.selectedApp)
    if (!target || !target.handle) {
      root.reportFocusError()
      return
    }

    root.pendingFocusHandle = target.handle
    focusAcknowledgementTimer.restart()
    var activated = false
    try {
      target.handle.activate()
      activated = root.pendingFocusHandle
        && root.pendingFocusHandle.activated === true
    } catch (error) {
      root.clearPendingFocus()
      root.reportFocusError()
      return
    }
    if (activated) root.dismiss()
  }

  function requestGracefulClose() {
    root.clearPendingFocus()
    root.footerMessage = ""
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
    if (!root.selectedApp) {
      root.footerMessage = "Unable to request Force Kill."
      return
    }

    root.pendingForceKillApp = {
      name: root.selectedApp.name,
      windowCount: root.selectedApp.windows.length,
      windows: root.selectedApp.windows.slice(0)
    }
    forceKillConfirm.selectedIndex = 1
    root.restoreListFocus()
  }

  function completeForceKill(confirmed) {
    var pendingApp = root.pendingForceKillApp
    root.pendingForceKillApp = null
    root.footerMessage = ""
    var targets = ProcDeckModel.forceKillTargets(pendingApp, confirmed)
    if (!confirmed) {
      root.restoreListFocus()
      return
    }
    var failures = 0

    for (var i = 0; i < targets.length; i++) {
      try {
        Hyprland.dispatch("killwindow " + targets[i])
      } catch (error) {
        failures++
      }
    }

    if (!targets.length)
      root.footerMessage = "No valid Force Kill targets."
    else if (failures === targets.length)
      root.footerMessage = "Unable to send Force Kill request."
    else if (failures)
      root.footerMessage = "Some Force Kill requests could not be sent."
    else
      root.footerMessage = "Force Kill requested for " + targets.length
        + (targets.length === 1 ? " owner." : " owners.")
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
    root.footerMessage = "Unable to focus this app."
    root.restoreListFocus()
  }

  function close() {
    root.clearPendingFocus()
    root.clearForceKillConfirmation()
    root.opened = false
  }

  function dismiss() {
    root.clearPendingFocus()
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
            root.focusSelectedApp()
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
            ? "Force Kill “" + root.pendingForceKillApp.name + "” and its "
              + root.pendingForceKillApp.windowCount
              + (root.pendingForceKillApp.windowCount === 1
                ? " App Window?" : " App Windows?")
              + " Unsaved work may be lost."
            : ""
          confirmText: "Force Kill"
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
              text: "Running Apps"
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.weight: Font.DemiBold
            }

            Text {
              Layout.fillWidth: true
              text: root.searchQuery || "Type to search…"
              textFormat: Text.PlainText
              color: root.foreground
              opacity: root.searchQuery ? 1 : 0.58
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }
          }

          Text {
            text: root.allApps.length + (root.allApps.length === 1 ? " app" : " apps")
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

        GridLayout {
          id: contentGrid
          Layout.fillWidth: true
          Layout.fillHeight: true
          columns: root.narrow ? 1 : 2
          rows: root.narrow ? 2 : 1
          columnSpacing: Style.spacing.panelGap
          rowSpacing: Style.spacing.panelGap

          Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: root.narrow ? contentGrid.width : contentGrid.width * 0.62
            Layout.preferredHeight: root.narrow ? contentGrid.height * 0.66 : contentGrid.height

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
                      text: appRow.modelData.windowCount
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
                    root.focusSelectedApp()
                  }
                }
              }

              Text {
                visible: root.apps.length === 0
                anchors.centerIn: parent
                width: parent.width - Style.spacing.panelPadding * 2
                text: root.allApps.length === 0
                  ? "No Running Apps"
                  : "No matches for “" + root.searchQuery + "”"
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
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: root.narrow ? contentGrid.width : contentGrid.width * 0.38
            Layout.preferredHeight: root.narrow ? contentGrid.height * 0.34 : contentGrid.height
            radius: root.cornerRadius
            color: Style.normalFill
            borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
            padding: Style.spacing.panelPadding

            ColumnLayout {
              anchors.fill: parent
              anchors.topMargin: parent.contentTopInset
              anchors.rightMargin: parent.contentRightInset
              anchors.bottomMargin: parent.contentBottomInset
              anchors.leftMargin: parent.contentLeftInset
              spacing: Style.spacing.md

              Text {
                Layout.fillWidth: true
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
                text: root.selectedApp && root.selectedApp.currentTitle
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

              Item { Layout.fillHeight: true }

              Text {
                Layout.fillWidth: true
                text: root.selectedApp && root.selectedApp.appId
                  ? root.selectedApp.appId : "Unidentified App"
                textFormat: Text.PlainText
                color: root.foreground
                opacity: 0.5
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                elide: Text.ElideMiddle
              }

              Button {
                Layout.fillWidth: true
                text: "Focus"
                bordered: true
                enabled: root.selectedApp !== null
                opacity: enabled ? 1 : 0.5
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.focusSelectedApp()
              }

              Button {
                Layout.fillWidth: true
                text: "Close"
                bordered: true
                enabled: root.selectedApp !== null
                opacity: enabled ? 1 : 0.5
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.requestGracefulClose()
              }

              Button {
                Layout.fillWidth: true
                text: "Force Kill"
                bordered: true
                enabled: root.selectedApp !== null
                opacity: enabled ? 1 : 0.5
                foreground: Color.urgent
                fontFamily: root.fontFamily
                onClicked: root.requestForceKill()
              }
            }
          }
        }

        Text {
          Layout.fillWidth: true
          text: root.footerMessage
            || "Enter / Click  Focus  ·  Delete  Close Request  ·  Shift+Delete  Force Kill  ·  ↑↓  Select  ·  PgUp/PgDn  Page  ·  Home/End  Jump  ·  Esc  Clear / Close"
          textFormat: Text.PlainText
          horizontalAlignment: Text.AlignRight
          color: root.foreground
          opacity: root.footerMessage ? 1 : 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
