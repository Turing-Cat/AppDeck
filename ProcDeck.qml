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
  property var activityIdentities: []
  property string searchQuery: ""
  property string selectedIdentity: ""

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  readonly property int cornerRadius: Style.cornerRadius
  readonly property string fontFamily: Style.font.menuFamily
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
      var workspace = hyprlandToplevel.workspace
      var workspaceId = workspace ? workspace.id : ""
      var workspaceName = workspace ? String(workspace.name || "").trim() : ""

      out.push({
        id: String(hyprlandToplevel.address || i),
        handle: waylandToplevel,
        parent: waylandToplevel ? waylandToplevel.parent : null,
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
    var nextApps = ProcDeckModel.orderRunningApps(groupedApps, root.activityIdentities)

    root.activityIdentities = nextApps.map(function(app) { return app.identity })
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
    root.searchQuery = ""
    root.rebuild()
    root.selectedIdentity = ProcDeckModel.initialSelectedIdentity(root.apps)
    root.opened = true
    Qt.callLater(function() {
      keyCatcher.forceActiveFocus()
      root.revealSelected()
    })
  }

  function setSearchQuery(query) {
    var previousIndex = root.selectedIndex
    root.searchQuery = query
    root.apps = ProcDeckModel.filterRunningApps(root.allApps, query)
    root.selectedIdentity = ProcDeckModel.reconcileSelectedIdentity(
      root.selectedIdentity, previousIndex, root.apps)
    root.revealSelected()
  }

  function select(delta) {
    if (!root.apps.length) return
    var index = root.selectedIndex
    if (index < 0) index = delta < 0 ? root.apps.length - 1 : 0
    else index = ((index + delta) % root.apps.length + root.apps.length) % root.apps.length
    root.selectedIdentity = root.apps[index].identity
    root.revealSelected()
  }

  function selectAbsolute(index) {
    if (!root.apps.length) return
    index = Math.max(0, Math.min(index, root.apps.length - 1))
    root.selectedIdentity = root.apps[index].identity
    root.revealSelected()
  }

  function revealSelected() {
    Qt.callLater(function() {
      if (root.selectedIndex >= 0)
        appList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
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

  Connections {
    target: Hyprland.toplevels
    function onValuesChanged() { root.scheduleRebuild() }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) { root.scheduleRebuild() }
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() { root.scheduleRebuild() }
  }

  Component.onCompleted: root.rebuild()

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
        focus: root.opened

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.searchQuery) root.setSearchQuery("")
            else root.dismiss()
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
            root.select(-6)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.select(6)
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
                height: Style.space(64)
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
                  onClicked: root.selectAbsolute(appRow.index)
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
            }
          }
        }

        Text {
          Layout.fillWidth: true
          text: "↑↓  Select  ·  PgUp/PgDn  Page  ·  Home/End  Jump  ·  Esc  Clear / Close"
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
