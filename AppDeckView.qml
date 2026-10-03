import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "AppDeckModel.js" as AppDeckModel

PanelWindow {
  id: panel
  required property var controller
  readonly property var root: controller
  readonly property bool composing: searchInput.inputMethodComposing && searchInput.preeditText.length > 0
  readonly property int pageSize: Math.max(1, Math.floor(
    (appList.height + appList.spacing) / (root.rowHeight + appList.spacing)))
  readonly property bool compactActions: detailCard.width < Style.space(440)

  function setInputText(query) {
    if (searchInput.text !== query) searchInput.text = query
  }
  function resetComposition() {
    if (searchInput.activeFocus) Qt.inputMethod.reset()
  }
  function focusInput() { searchInput.forceActiveFocus() }
  function focusControls() {
    if (root.pendingForceKillApp) keyCatcher.forceActiveFocus()
    else focusInput()
  }
  function beginConfirmation() { forceKillConfirm.selectedIndex = 1 }
  function handleConfirmation(event) { return forceKillConfirm.handleKey(event) }
  function revealApp(index) { appList.positionViewAtIndex(index, ListView.Contain) }
  function revealWindow(index) { windowList.positionViewAtIndex(index, ListView.Contain) }

  visible: root.opened
  anchors { top: true; right: true; bottom: true; left: true }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "appdeck"
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
      Keys.onPressed: function(event) { root.handleKey(event) }

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

          TextInput {
            id: searchInput
            Layout.fillWidth: true
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            selectionColor: root.selectedBackground
            selectedTextColor: root.selectedText
            selectByMouse: true
            clip: true
            onTextEdited: root.setSearchQuery(text)
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) { root.handleKey(event) }

            Text {
              anchors.fill: parent
              visible: !searchInput.text && !searchInput.preeditText
              text: "Type to search…"
              textFormat: Text.PlainText
              color: root.foreground
              opacity: 0.58
              font: searchInput.font
            }
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

      GridLayout {
        id: contentLayout
        columns: card.width < Style.space(720) ? 1 : 2
        columnSpacing: Style.spacing.panelGap
        rowSpacing: Style.spacing.panelGap
        Layout.fillWidth: true
        Layout.fillHeight: true

        Item {
          Layout.preferredWidth: contentLayout.columns === 2 ? contentLayout.width * 0.37 : -1
          Layout.fillWidth: contentLayout.columns === 1
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
          Layout.fillHeight: contentLayout.columns === 2
          Layout.preferredHeight: Style.space(280)
          Layout.minimumHeight: Style.space(240)
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
              visible: !root.selectedApp || root.selectedApp.kind === "launch"
              Layout.fillWidth: true
              Layout.fillHeight: true
              text: root.selectedApp ? "Installed application · Ready to start" : "No selection"
              textFormat: Text.PlainText
              color: root.foreground
              opacity: 0.58
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.Wrap
            }

            ListView {
              id: windowList
              readonly property var recentWindow: AppDeckModel.mostRecentlyActiveAppWindow(root.selectedApp)
              visible: root.selectedApp !== null && root.selectedApp.kind === "running"
              Layout.fillWidth: true
              Layout.fillHeight: true
              clip: true
              spacing: Style.spacing.sm
              model: visible ? root.selectedApp.windows : []
              onModelChanged: {
                if (root.windowSelectionActive) root.revealSelectedWindow()
                else positionViewAtBeginning()
              }

              delegate: BorderSurface {
                id: windowRow
                objectName: "appWindow:" + modelData.id
                required property var modelData
                readonly property bool recent: windowList.recentWindow !== null
                  && modelData.id === windowList.recentWindow.id
                readonly property bool selected: root.windowSelectionActive
                  ? modelData.id === root.selectedWindowId : recent
                width: ListView.view.width
                height: windowInfo.implicitHeight + Style.spacing.rowPaddingX * 2
                radius: root.cornerRadius
                color: selected ? root.selectedBackground
                  : windowMouse.containsMouse ? Style.normalFill : root.background
                borderSpec: Border.controlSpec(selected ? "selected" : "normal", root.foreground, Color.accent)

                ColumnLayout {
                  id: windowInfo
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.margins: Style.spacing.rowPaddingX
                  spacing: Style.spacing.xs

                  Text {
                    Layout.fillWidth: true
                    text: modelData.title || "Untitled window"
                    textFormat: Text.PlainText
                    color: windowRow.selected ? root.selectedText : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                  }

                  Text {
                    Layout.fillWidth: true
                    text: (modelData.workspace ? "Workspace " + modelData.workspace : "No workspace")
                      + (recent ? " · Most recent" : "")
                    textFormat: Text.PlainText
                    color: windowRow.selected ? root.selectedText : root.foreground
                    opacity: 0.58
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                MouseArea {
                  id: windowMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.chooseWindow(windowRow.modelData.id)
                    root.focusSelectedApp()
                  }
                }
              }
            }

            Rectangle {
              Layout.fillWidth: true
              height: Style.spacing.hairline
              color: Util.alpha(root.foreground, 0.16)
            }

            GridLayout {
              Layout.fillWidth: true
              columns: 1
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
                Layout.fillWidth: panel.compactActions
                Layout.alignment: Qt.AlignRight
                spacing: Style.spacing.sm

                Button {
                  objectName: "focusSelected"
                  Layout.fillWidth: panel.compactActions
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
                  objectName: "closeSelected"
                  visible: root.selectedApp !== null
                    && root.selectedApp.kind === "running"
                  Layout.fillWidth: panel.compactActions
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
                  objectName: "killSelected"
                  visible: root.selectedApp !== null
                    && root.selectedApp.kind === "running"
                  Layout.fillWidth: panel.compactActions
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
          text: (root.windowSelectionActive
            ? "↑↓ Apps · Tab / Shift+Tab Windows · Enter "
            : "↑↓ Apps · Tab Windows · Enter ")
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
