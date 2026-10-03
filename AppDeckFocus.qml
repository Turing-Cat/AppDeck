import QtQuick
import "AppDeckModel.js" as AppDeckModel

Item {
  id: focus
  required property var desktop
  required property var selection
  property var pendingFocusHandle: null
  property int generation: 0
  signal started()
  signal succeeded()
  signal failed()

  function request(target) {
    focus.cancel()
    target = target ? selection.windowById(target.id) : null
    var command = AppDeckModel.focusCommand(target)
    if (!target || !target.handle || !command) {
      focus.fail()
      return
    }

    focus.pendingFocusHandle = target.handle
    var appIdentity = selection.selectedIdentity
    var targetId = target.id
    started()
    var requestGeneration = generation
    Qt.callLater(function() {
      if (requestGeneration !== generation || !focus.pendingFocusHandle) return
      var current = selection.selectedIdentity === appIdentity ? selection.windowById(targetId) : null
      if (!current || current.handle !== focus.pendingFocusHandle) {
        focus.fail()
        return
      }
      focusAcknowledgementTimer.restart()
      try {
        desktop.focusWindow(current)
        if (focus.pendingFocusHandle
            && focus.pendingFocusHandle.activated === true)
          focus.succeed()
      } catch (error) {
        focus.fail()
      }
    })
  }

  function cancel() {
    generation++
    focusAcknowledgementTimer.stop()
    pendingFocusHandle = null
  }

  function fail() { cancel(); failed() }
  function succeed() { cancel(); succeeded() }

  Timer {
    id: focusAcknowledgementTimer
    interval: 250
    repeat: false
    onTriggered: focus.fail()
  }

  Connections {
    target: focus.pendingFocusHandle
    function onActivatedChanged() {
      if (focus.pendingFocusHandle
          && focus.pendingFocusHandle.activated === true)
        focus.succeed()
    }
  }

}
