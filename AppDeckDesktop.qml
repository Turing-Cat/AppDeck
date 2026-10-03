import QtQuick
import Quickshell
import Quickshell.Hyprland
import "AppDeckModel.js" as AppDeckModel

Item {
  id: desktop
  signal changed()
  readonly property bool killAvailable: !!Hyprland.requestSocketPath
  property Component killRequest: Component {
    AppDeckKillRequest { path: Hyprland.requestSocketPath }
  }

  function lookupApp(appId) { return DesktopEntries.heuristicLookup(appId) }
  function refresh() { Hyprland.refreshToplevels() }
  function focusWindow(window) { Hyprland.dispatch(AppDeckModel.focusCommand(window)) }

  function snapshots() {
    var values = Hyprland.toplevels.values || []
    var out = []
    var seenAddresses = ({})

    for (var i = 0; i < values.length; i++) {
      var hyprlandToplevel = values[i]
      var waylandToplevel = hyprlandToplevel.wayland
      var address = AppDeckModel.normalizedHyprlandAddress(
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

  Connections {
    target: Hyprland.toplevels
    function onValuesChanged() { desktop.changed() }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event ? String(event.name) : ""
      if (name === "activewindow" || name === "activewindowv2")
        Hyprland.refreshToplevels()
      desktop.changed()
    }
  }

  Instantiator {
    model: Hyprland.toplevels.values || []
    delegate: Connections {
      required property var modelData
      target: modelData
      function onLastIpcObjectChanged() { desktop.changed() }
      function onWaylandHandleChanged() { desktop.changed() }
    }
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() { desktop.changed() }
  }
}
