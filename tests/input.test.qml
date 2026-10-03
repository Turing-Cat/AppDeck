import QtQuick
import Quickshell
import Quickshell.Wayland
import InputTest 1.0

ShellRoot {
  id: test
  property var app: null
  property int launches: 0
  property int closes: 0
  property bool failLaunch: false
  property var steps: []
  property int step: 0
  InputEvents { id: input }

  // Only desktop data and external actions are replaced; AppDeck owns all
  // input, query synchronization, selection, and confirmation behavior.
  QtObject {
    id: library
    signal appsChanged()
    function sortedEntries(query) {
      return [
        { entry: { id: "appdeck-test-zh", name: "中文" } },
        { entry: { id: "appdeck-test-long", name: "中文输入" } },
        { entry: { id: "appdeck-test-en", name: "English" } }
      ]
    }
    function launch(id, name) {
      test.launches++
      if (test.failLaunch) throw new Error("test launch failure")
    }
  }
  QtObject {
    id: fixtureShell
    property var appLibrary: library
    function hide(id) {}
  }
  QtObject {
    id: fixtureWindow
    property bool activated: false
    function close() { test.closes++ }
  }
  QtObject {
    id: secondWindow
    property bool activated: false
    function close() { test.closes++ }
  }
  QtObject {
    id: thirdWindow
    property bool activated: false
    function close() { test.closes++ }
  }

  QtObject {
    id: desktop
    signal changed()
    property var rows: []
    property var metadata: ({})
    property var focusedIds: []
    property bool acknowledgeFocus: false
    property bool throwFocus: false
    property bool killAvailable: true
    property bool succeedKill: true
    property bool holdKill: false
    property var deliveries: []
    property Component killRequest: Component {
      QtObject {
        required property string command
        signal completed(bool succeeded)
        function start() {
          desktop.deliveries = desktop.deliveries.concat([this])
          if (!desktop.holdKill) completed(desktop.succeedKill)
        }
      }
    }
    function snapshots() { return rows }
    function lookupApp(id) { return metadata[id] || null }
    function refresh() {}
    function focusWindow(window) {
      focusedIds = focusedIds.concat([window.id])
      if (throwFocus) throw new Error("fixture dispatch failure")
      if (acknowledgeFocus) window.handle.activated = true
    }
  }

  // Publish desktop observations; the production model does grouping,
  // ordering, search and stable selection, just as it does for Hyprland.
  function publishApps(apps) {
    var rows = []
    var metadata = ({})
    for (var a = 0; a < apps.length; a++) {
      var app = apps[a]
      var id = app.identity.slice(4)
      metadata[id] = { id: id, name: app.name, icon: app.icon }
      for (var w = 0; w < app.windows.length; w++)
        rows.push(Object.assign({}, app.windows[w], { appId: id }))
    }
    desktop.metadata = metadata
    desktop.rows = rows
    desktop.changed()
    test.app.rebuild()
  }

  function check(condition, message) {
    if (!condition) throw new Error(message)
  }

  function query(expected) {
    check(test.app.searchQuery === expected, "Search Query: expected [" + expected + "], received [" + test.app.searchQuery + "]")
    check(input.focus().text === expected, "input text differs from Search Query")
  }

  function composeOnRunningApp() {
    input.compose("", "")
    setRunningFixture()
    test.app.setSearchQuery("AppDeck Test")
    input.compose("zhongwen")
    check(input.focus().inputMethodComposing, "input is not composing")
  }

  function setRunningFixture() {
    publishApps([{ kind: "running", identity: "app:appdeck-test", appId: "AppDeck Test",
      name: "AppDeck Test", icon: "", windowCount: 1, workspaces: ["1"], currentTitle: "Fixture",
      windows: [{ id: "fixture", title: "Fixture", workspace: "1", handle: fixtureWindow,
        ownerIdentity: 2147483647, hyprlandAddress: "ffffffffffffffff" }] }])
  }

  function setMultiWindowFixture() {
    publishApps([{ kind: "running", identity: "app:appdeck-test", appId: "AppDeck Test",
      name: "AppDeck Test", icon: "", windowCount: 3, workspaces: ["1", "2", "3"], currentTitle: "Second",
      windows: [
        { id: "first", title: "First", workspace: "1", handle: fixtureWindow, focusHistoryId: 2, hyprlandAddress: "fffffffffffffff1" },
        { id: "second", title: "Second", workspace: "2", handle: secondWindow, focusHistoryId: 0, hyprlandAddress: "fffffffffffffff2" },
        { id: "third", title: "Third", workspace: "3", handle: thirdWindow, focusHistoryId: 1, hyprlandAddress: "fffffffffffffff3" }
      ] }])
    test.app.setSearchQuery("AppDeck Test")
  }

  function finish(code) {
    if (test.app) test.app.close()
    input.finish(code)
  }

  Component.onCompleted: {
    var component = Qt.createComponent("file://" + Quickshell.env("APPDECK_TEST_REPO") + "/AppDeck.qml")
    if (component.status !== Component.Ready) {
      console.error(component.errorString())
      test.finish(1)
      return
    }
    test.app = component.createObject(test, { desktop: desktop })
    if (!test.app) { test.finish(1); return }
    // Synthetic events go through the real window, without grabbing the
    // desktop keyboard or accepting keystrokes from the person running it.
    for (var i = 0; i < test.app.data.length; i++) {
      var child = test.app.data[i]
      if (child.contentItem !== undefined)
        child.WlrLayershell.keyboardFocus = WlrKeyboardFocus.None
    }
    test.app.shell = fixtureShell
    test.app.open("{}")
    test.steps = [
      function chineseCommit() {
        check(input.focus(), "AppDeck has no focused input receiver")
        input.compose("", "中文")
        query("中文")
        check(test.app.selectedApp.name === "中文", "Chinese query did not select the matching app")
      },
      function continuousComposition() {
        test.app.setSearchQuery("")
        input.compose("zhongwen")
        query("")
        check(input.focus().preeditText === "zhongwen", "preedit text is missing")
        input.compose("", "中文")
        query("中文")
        input.compose("shuru")
        query("中文")
        input.compose("", "输入")
        query("中文输入")
      },
      function mixedTextAndPaste() {
        test.app.setSearchQuery("")
        input.key(Qt.Key_A, Qt.NoModifier, "a")
        input.compose("", "中文")
        input.paste("b测试")
        query("a中文b测试")
      },
      function nativeEditing() {
        test.app.setSearchQuery("中文输入")
        input.key(Qt.Key_Backspace)
        query("中文输")
        input.key(Qt.Key_Left)
        var cursor = input.focus().cursorPosition
        input.key(Qt.Key_X, Qt.NoModifier, "x")
        query("中文x输")
        check(input.focus().cursorPosition === cursor + 1, "editing reset the cursor")
        input.key(Qt.Key_A, Qt.ControlModifier)
        input.compose("", "替换")
        query("替换")
        input.key(Qt.Key_U, Qt.ControlModifier)
        query("")
        input.compose("", "继续")
        query("继续")
        test.app.setSearchQuery("中文 English")
        input.key(Qt.Key_Backspace, Qt.ControlModifier)
        query("中文 ")
      },
      function compositionShortcutsAndNavigation() {
        var keys = [Qt.Key_Return, Qt.Key_Enter, Qt.Key_Delete, Qt.Key_Delete,
          Qt.Key_Escape, Qt.Key_Up, Qt.Key_Down, Qt.Key_PageUp, Qt.Key_PageDown, Qt.Key_Home, Qt.Key_End]
        for (var i = 0; i < keys.length; i++) {
          composeOnRunningApp()
          var selected = test.app.selectedIdentity
          input.key(keys[i], i === 3 ? Qt.ShiftModifier : Qt.NoModifier)
          check(test.app.opened, "composing key closed AppDeck: " + keys[i])
          check(test.app.selectedIdentity === selected, "composing key changed Selected App: " + keys[i])
          check(test.app.searchQuery === "AppDeck Test", "composing key cleared the query")
          check(test.launches === 0 && test.closes === 0, "composing key invoked an external action")
          check(!test.app.pendingFocusHandle && !test.app.pendingForceKillApp && !test.app.forceKillRequests.length,
            "composing key requested Focus or Kill")
        }
        input.compose("", "")
        test.app.setSearchQuery("")
        input.key(Qt.Key_End)
        check(test.app.selectedIndex === test.app.apps.length - 1, "End did not select the last app")
        input.key(Qt.Key_Home)
        check(test.app.selectedIndex === 0, "Home did not select the first app")
        input.key(Qt.Key_Down)
        check(test.app.selectedIndex === 1, "Down did not move selection")
        input.key(Qt.Key_Up)
        check(test.app.selectedIndex === 0, "Up did not move selection")
        input.key(Qt.Key_PageDown)
        check(test.app.selectedIndex > 0, "Page Down did not move selection")
        input.key(Qt.Key_PageUp)
        check(test.app.selectedIndex === 0, "Page Up did not move selection")
      },
      function closeAndKillConfirmation() {
        setRunningFixture()
        test.app.setSearchQuery("AppDeck Test")
        input.compose("", "", true)
        check(input.focus().inputMethodComposing && !input.focus().preeditText,
          "empty cursor-attribute input-method state was not reproduced")
        input.key(Qt.Key_Delete)
        check(test.closes === 1, "Delete did not send the Close Request")
        input.key(Qt.Key_Delete, Qt.ShiftModifier)
        check(test.app.pendingForceKillApp, "Shift + Delete did not open confirmation")
        check(!test.app.forceKillRequests.length, "Kill ran without confirmation")
      },
      function cancelKill() {
        input.key(Qt.Key_Escape)
        check(!test.app.pendingForceKillApp, "Escape did not cancel Kill confirmation")
      },
      function restoreInputAndActivate() {
        query("AppDeck Test")
        input.compose("", "中文")
        query("AppDeck Test中文")
        test.app.setSearchQuery("中文")
        input.key(Qt.Key_Return)
      },
      function launchedAppAndReopen() {
        check(test.launches === 1 && !test.app.opened, "Enter did not launch the selected app")
        test.failLaunch = true
        test.app.open("{}")
      },
      function requestFailedLaunch() {
        test.app.setSearchQuery("中文")
        input.key(Qt.Key_Return)
      },
      function recoverLaunchAndCloseComposition() {
        check(test.app.opened && test.app.footerMessage === "Unable to start this app.", "launch failure did not restore AppDeck")
        query("中文")
        input.compose("", "输入")
        query("中文输入")
        input.compose("canshu")
        test.app.close()
        test.app.open("{}")
      },
      function reopenAndEscape() {
        query("")
        check(!input.focus().inputMethodComposing && !input.focus().preeditText, "reopen left stale composition")
        input.compose("", "中文")
        input.key(Qt.Key_Escape)
        query("")
        check(test.app.opened, "Escape closed AppDeck instead of clearing query")
        input.key(Qt.Key_Escape)
        check(!test.app.opened, "Escape on an empty query did not close AppDeck")
        test.app.open("{}")
      },
      function requestFailedFocus() {
        query("")
        setRunningFixture()
        test.app.setSearchQuery("AppDeck Test")
        input.key(Qt.Key_Return)
        run.interval = 350
      },
      function recoverFocus() {
        check(test.app.opened && test.app.footerMessage === "Unable to focus this app.", "Focus failure did not restore AppDeck")
        query("AppDeck Test")
        input.compose("", "中文")
        query("AppDeck Test中文")
      },
      function windowKeyboardSelection() {
        setMultiWindowFixture()
        input.key(Qt.Key_Tab)
        check(test.app.selectedWindowId === "second", "first Tab did not select the most recent window")
        query("AppDeck Test")
        input.key(Qt.Key_Tab)
        check(test.app.selectedWindowId === "third", "Tab did not select next window")
        input.key(Qt.Key_Tab)
        check(test.app.selectedWindowId === "first", "Tab did not wrap to first window")
        input.key(Qt.Key_Backtab, Qt.ShiftModifier)
        check(test.app.selectedWindowId === "third", "Backtab did not wrap to last window")
        input.key(Qt.Key_Tab, Qt.ShiftModifier)
        check(test.app.selectedWindowId === "second", "Shift+Tab did not select previous window")
        input.key(Qt.Key_Delete)
        input.key(Qt.Key_Delete, Qt.ShiftModifier)
        check(test.closes === 1 && !test.app.pendingForceKillApp, "window selection invoked Close or Kill")
        input.key(Qt.Key_X, Qt.NoModifier, "x")
        check(!test.app.selectedWindowId, "search editing did not exit window selection")
        query("AppDeck Testx")
      },
      function windowNavigationAndComposition() {
        setMultiWindowFixture()
        input.key(Qt.Key_Tab)
        input.key(Qt.Key_Tab, Qt.ControlModifier)
        check(test.app.selectedWindowId === "second", "Ctrl+Tab changed window selection")
        input.compose("zhongwen")
        input.key(Qt.Key_Tab)
        check(test.app.selectedWindowId === "second", "composing Tab changed window selection")
        input.compose("", "", true)
        input.key(Qt.Key_Tab)
        check(test.app.selectedWindowId === "third", "empty Fcitx state blocked Tab")
        input.compose("", "中文")
        query("AppDeck Test中文")
        check(!test.app.selectedWindowId, "Chinese commit did not exit window selection")
        test.app.setSearchQuery("")
        test.app.selectAbsolute(0)
        input.key(Qt.Key_Tab)
        check(test.app.selectedWindowId, "running app did not enter window selection")
        input.key(Qt.Key_Down)
        check(test.app.selectedIndex === 1 && !test.app.selectedWindowId, "Down did not switch apps and exit window selection")
        input.key(Qt.Key_Tab)
        check(!test.app.selectedWindowId, "Launchable App entered window selection")
        input.key(Qt.Key_Up)
        check(test.app.selectedIndex === 0, "Up did not switch apps")
      },
      function liveWindowSelection() {
        setMultiWindowFixture()
        input.key(Qt.Key_Tab)
        input.key(Qt.Key_Tab)
        var original = test.app.selectedApp
        // Replace desktop snapshots, preserving identity but changing order,
        // title and workspace; new window objects must not steal selection.
        var updated = Object.assign({}, original, { windows: [
          Object.assign({}, original.windows[2], { title: "Moved", workspace: "9" }),
          original.windows[0], original.windows[1],
          { id: "new", title: "New", workspace: "4", handle: fixtureWindow, hyprlandAddress: "fffffffffffffff4" }
        ], windowCount: 4 })
        publishApps([updated])
        check(test.app.selectedWindowId === "third" && test.app.selectedWindow.workspace === "9",
          "desktop update lost the selected window")
        publishApps([Object.assign({}, updated, { windows: updated.windows.slice(1), windowCount: 3 })])
        check(!test.app.selectedWindowId && test.app.opened, "removed window did not clear selection")
        check(test.app.footerMessage.indexOf("no longer available") >= 0, "removed window has no error message")
        check(!test.app.pendingFocusHandle, "removed window silently requested another target")
      },
      function singleWindowAndUnknownRecent() {
        setRunningFixture()
        test.app.setSearchQuery("AppDeck Test")
        input.key(Qt.Key_Backtab, Qt.ShiftModifier)
        input.key(Qt.Key_Tab)
        check(test.app.selectedWindowId === "fixture", "single window cycling failed")
        setMultiWindowFixture()
        var app = test.app.selectedApp
        publishApps([Object.assign({}, app, { windows: app.windows.map(function(w) {
          return Object.assign({}, w, { focusHistoryId: null })
        }) })])
        input.key(Qt.Key_Tab)
        check(test.app.selectedWindowId === "first", "unknown recent window did not fall back to first")
        input.key(Qt.Key_Escape)
        query("")
        check(!test.app.selectedWindowId && test.app.opened, "Escape did not clear query and window selection")
        input.key(Qt.Key_Escape)
        check(!test.app.opened, "empty Escape did not close AppDeck")
        test.app.open("{}")
      },
      function requestSpecifiedWindow() {
        setMultiWindowFixture()
        input.key(Qt.Key_Tab)
        input.key(Qt.Key_Tab)
        input.key(Qt.Key_Return)
        check(test.app.pendingFocusHandle === thirdWindow, "Enter requested the recent window instead of selected window")
        run.interval = 350
      },
      function recoverSpecifiedWindow() {
        check(test.app.opened && test.app.footerMessage === "Unable to focus this window.", "specified Focus failure did not recover: " + test.app.footerMessage + ", selected=" + test.app.selectedIdentity + ", window=" + test.app.selectedWindowId)
        check(test.app.selectedWindowId === "third", "Focus failure lost explicit selection")
        query("AppDeck Test")
        input.mouse("appWindow:first", false)
        check(test.app.selectedWindowId === "third", "hover changed window selection")
        input.mouse("appWindow:first")
        check(test.app.pendingFocusHandle === fixtureWindow && test.app.selectedWindowId === "first", "mouse did not request clicked window")
      },
      function focusButtonAndAppActions() {
        check(test.app.opened, "mouse Focus failure did not restore AppDeck")
        query("AppDeck Test")
        input.key(Qt.Key_Tab)
        check(test.app.selectedWindowId === "second", "Tab did not continue from clicked window")
        input.mouse("focusSelected")
        check(test.app.pendingFocusHandle === secondWindow, "Focus button did not request selected window")
      },
      function closeAndKillButtonsInWindowSelection() {
        check(test.app.opened, "Focus button failure did not restore AppDeck")
        var before = test.closes
        input.mouse("closeSelected")
        check(test.closes === before + 3, "Close button did not target all app windows")
        input.mouse("killSelected")
        check(test.app.pendingForceKillApp && test.app.pendingForceKillApp.windowCount === 3, "Kill button did not keep app scope")
        check(!test.app.forceKillRequests.length, "Kill button bypassed confirmation")
        var selected = test.app.selectedWindowId
        input.key(Qt.Key_Tab)
        check(test.app.selectedWindowId === selected, "confirmation Tab cycled app windows")
        input.key(Qt.Key_Escape)
      },
      function restoreAfterConfirmation() {
        query("AppDeck Test")
        check(test.app.selectedWindowId === "second", "Kill cancellation lost valid window selection")
        input.compose("", "中文")
        query("AppDeck Test中文")
        check(!test.app.selectedWindowId, "input after confirmation did not reset window selection")
      },
      function disappearedBeforeDispatch() {
        setMultiWindowFixture()
        input.key(Qt.Key_Tab)
        input.key(Qt.Key_Return)
        check(test.app.pendingFocusHandle === secondWindow, "explicit target was not requested")
        var app = test.app.selectedApp
        publishApps([Object.assign({}, app, { windows: [app.windows[0], app.windows[2]], windowCount: 2 })])
        check(!test.app.pendingFocusHandle && test.app.opened && !test.app.selectedWindowId,
          "target removed before dispatch did not cancel and restore")
      },
      function manyWindowSelection() {
        setMultiWindowFixture()
        var app = test.app.selectedApp
        var windows = []
        for (var i = 0; i < 14; i++) windows.push(Object.assign({}, app.windows[0], {
          hyprlandAddress: (4096 + i).toString(16), id: "long-" + i, title: "Long window " + i, focusHistoryId: i
        }))
        publishApps([Object.assign({}, app, { windows: windows, windowCount: windows.length })])
        input.key(Qt.Key_Tab)
        input.key(Qt.Key_Backtab, Qt.ShiftModifier)
        check(test.app.selectedWindowId === "long-13", "reverse cycling did not select last window")
      },
      function visibleWindowAndAppNavigation() {
        var row = input.item("appWindow:long-13")
        check(row && row.selected, "selected row was not created or highlighted after scrolling")
        check(row.mapToItem(null, 0, 0).y > 0, "selected row remained above viewport")
        var app = test.app.selectedApp
        publishApps([Object.assign({}, app, { windows: app.windows.map(function(w) {
          return Object.assign({}, w, { title: "Updated " + w.title })
        }) })])
        check(test.app.selectedWindowId === "long-13", "title refresh lost scrolled selection")
        input.key(Qt.Key_Home)
        check(!test.app.selectedWindowId && test.app.selectedIndex === 0, "Home did not exit window selection")
        input.key(Qt.Key_Tab)
        input.key(Qt.Key_PageDown)
        check(!test.app.selectedWindowId, "Page Down did not exit window selection")
        test.app.setSearchQuery("no-such-appdeck-test-app")
        input.key(Qt.Key_Tab)
        check(!test.app.selectedWindowId && test.app.apps.length === 0, "empty results entered window selection")
        test.app.close()
        test.app.open("{}")
        check(!test.app.selectedWindowId, "reopen retained explicit window selection")
      },
      function successfulFocus() {
        setMultiWindowFixture()
        desktop.acknowledgeFocus = true
        desktop.focusedIds = []
        input.key(Qt.Key_Tab)
        input.key(Qt.Key_Return)
        check(!test.app.opened && test.app.pendingFocusHandle === secondWindow,
          "focus did not hide the panel and retain the exact pending handle")
      },
      function acknowledgedFocus() {
        check(!test.app.opened && !test.app.pendingFocusHandle, "focus acknowledgement did not finish")
        check(desktop.focusedIds.join() === "second", "focus dispatched the wrong window")
        desktop.acknowledgeFocus = false
        secondWindow.activated = false
        test.app.open("{}")
        desktop.focusedIds = []
        setMultiWindowFixture()
        test.app.focusSelectedApp()
        test.app.close()
      },
      function cancelledFocus() {
        check(desktop.focusedIds.length === 0, "cancelled deferred focus still dispatched")
        test.app.open("{}")
        setMultiWindowFixture()
        desktop.focusedIds = []
        desktop.acknowledgeFocus = true
        test.app.focusWindow(test.app.selectedApp.windows[0])
        test.app.focusWindow(test.app.selectedApp.windows[2])
      },
      function replacedFocus() {
        check(desktop.focusedIds.join() === "third", "replaced focus dispatched stale work")
        check(!test.app.pendingFocusHandle && !test.app.opened, "replacement focus failed to complete")
        thirdWindow.activated = false
        desktop.acknowledgeFocus = false
        test.app.open("{}")
        setMultiWindowFixture()
        desktop.throwFocus = true
        test.app.focusSelectedApp()
      },
      function thrownFocus() {
        check(test.app.opened && !test.app.pendingFocusHandle, "dispatch exception did not restore the panel")
        check(test.app.footerMessage === "Unable to focus this app.", "dispatch exception lost error message")
        desktop.throwFocus = false
        setRunningFixture()
        test.app.setSearchQuery("AppDeck Test")
        desktop.deliveries = []
        test.app.requestForceKill()
        test.app.completeForceKill(true)
        check(desktop.deliveries.length === 1, "confirmed Kill did not deliver exactly one owner request")
        check(desktop.deliveries[0].command.indexOf("0xffffffffffffffff") >= 0,
          "Kill delivery lost the exact desktop address")
      },
      function successfulKill() {
        check(test.app.forceKillRequests.length === 0, "Kill batch did not finish")
        check(test.app.footerMessage === "Kill requested for 1 owner.", "Kill success message differs")
        desktop.deliveries = []
        test.app.requestForceKill()
        desktop.rows = desktop.rows.map(function(w) { return Object.assign({}, w, { ownerIdentity: 123 }) })
        test.app.completeForceKill(true)
        check(desktop.deliveries.length === 0 && test.app.footerMessage.indexOf("target changed") >= 0,
          "changed owner escaped confirmation revalidation")
        setRunningFixture()
        test.app.setSearchQuery("AppDeck Test")
        test.app.requestForceKill()
        test.app.completeForceKill(false)
        check(desktop.deliveries.length === 0, "cancelled Kill delivered a command")
      },
      function sharedKillOwner() {
        setRunningFixture()
        test.app.setSearchQuery("AppDeck Test")
        test.app.requestForceKill()
        desktop.rows = desktop.rows.concat([Object.assign({}, desktop.rows[0], {
          id: "other", appId: "other-app", hyprlandAddress: "eeeeeeeeeeeeeeee"
        })])
        test.app.completeForceKill(true)
        check(desktop.deliveries.length === 0 && test.app.footerMessage.indexOf("shared") >= 0,
          "Kill targeted an owner shared with another Running App")
        setRunningFixture()
        test.app.setSearchQuery("AppDeck Test")
        desktop.killAvailable = false
        test.app.requestForceKill()
        test.app.completeForceKill(true)
        check(desktop.deliveries.length === 0 && test.app.footerMessage === "Unable to send Kill request.",
          "unavailable transport was used")
        desktop.killAvailable = true
      },
      function failedKill() {
        desktop.succeedKill = false
        test.app.requestForceKill()
        test.app.completeForceKill(true)
      },
      function failedKillResponse() {
        check(test.app.forceKillRequests.length === 0 && test.app.footerMessage === "Unable to send Kill request.",
          "failed Kill did not finish with its failure message")
        setMultiWindowFixture()
        desktop.rows = desktop.rows.map(function(w, i) { return Object.assign({}, w, { ownerIdentity: 100 + i }) })
        test.app.rebuild()
        desktop.deliveries = []
        desktop.holdKill = true
        test.app.requestForceKill()
        test.app.completeForceKill(true)
        check(desktop.deliveries.length === 3, "multi-owner Kill did not dispatch all owners")
        test.app.requestForceKill()
        check(test.app.footerMessage === "A Kill request is still pending.", "pending Kill was not guarded")
        desktop.deliveries[2].completed(true)
        desktop.deliveries[2].completed(true)
        desktop.deliveries[0].completed(false)
      },
      function partialKillResponse() {
        check(test.app.forceKillRequests.length === 3, "batch completed before every owner responded")
        desktop.deliveries[1].completed(true)
      },
      function completedPartialKill() {
        check(test.app.forceKillRequests.length === 0
          && test.app.footerMessage === "Some Kill requests could not be sent.",
          "duplicate or out-of-order responses corrupted Kill aggregation")
        desktop.holdKill = false
        desktop.succeedKill = true
        // Exercise the actual socket response parser without opening a socket.
        var component = Qt.createComponent("file://" + Quickshell.env("APPDECK_TEST_REPO") + "/AppDeckKillRequest.qml")
        check(component.status === Component.Ready, component.errorString())
        var request = component.createObject(test, { command: "unused", path: "" })
        check(request, "could not create native Kill response reader")
        var responses = []
        request.completed.connect(function(ok) { responses.push(ok) })
        request.acceptResponse("o", false)
        check(responses.length === 0, "partial socket response completed early")
        request.acceptResponse("k\n", false)
        request.acceptResponse("error", true)
        check(responses.length === 1 && responses[0], "fragmented acknowledgement or duplicate completion failed")
        request.destroy()
        var failed = component.createObject(test, { command: "unused", path: "" })
        var failures = []
        failed.completed.connect(function(ok) { failures.push(ok) })
        failed.acceptResponse("error", true)
        check(failures.length === 1 && !failures[0], "socket disconnect did not fail the request")
        failed.destroy()
      }

    ]
    run.start()
  }

  Timer {
    id: run
    interval: 100
    onTriggered: {
      try {
        test.steps[test.step]()
        console.log("PASS: " + test.steps[test.step].name)
        test.step++
        if (test.step < test.steps.length) run.start()
        else test.finish(0)
      } catch (error) {
        console.error("FAIL: " + test.steps[test.step].name + ": " + error.message)
        test.finish(1)
      }
    }
  }
}
