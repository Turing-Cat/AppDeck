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
    test.app.allApps = [{ kind: "running", identity: "app:appdeck-test", appId: "AppDeck Test",
      name: "AppDeck Test", icon: "", windowCount: 1, workspaces: ["1"], currentTitle: "Fixture",
      windows: [{ handle: fixtureWindow, ownerIdentity: 2147483647, hyprlandAddress: "ffffffffffffffff" }] }]
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
    test.app = component.createObject(test)
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
