import QtQuick
import "AppDeckModel.js" as AppDeckModel

Item {
  id: kill
  required property var desktop
  required property var selection
  required property var refresh
  property string message: ""
  signal settled()
  property var pendingForceKillApp: null
  property var forceKillRequests: []
  property int forceKillResponseCount: 0
  property int forceKillFailureCount: 0

  function requestForceKill() {
    message = ""
    if (kill.forceKillRequests.length) {
      message = "A Kill request is still pending."
      return
    }
    if (!selection.selectedApp || selection.selectedApp.kind !== "running") {
      message = "Unable to request Kill."
      return
    }

    kill.pendingForceKillApp = {
      identity: selection.selectedApp.identity,
      name: selection.selectedApp.name,
      windowCount: selection.selectedApp.windows.length,
      forceKillScope: AppDeckModel.forceKillScope(selection.selectedApp)
    }
    settled()
  }

  function completeForceKill(confirmed) {
    var pendingApp = kill.pendingForceKillApp
    kill.pendingForceKillApp = null
    message = ""
    var currentApp = null
    if (confirmed && pendingApp) {
      refresh()
      for (var i = 0; i < selection.allApps.length; i++) {
        if (selection.allApps[i].identity === pendingApp.identity) {
          currentApp = selection.allApps[i]
          break
        }
      }
    }
    var targets = AppDeckModel.forceKillTargets(
      currentApp || pendingApp, confirmed, selection.allApps)
    if (!confirmed) {
      settled()
      return
    }
    if (!currentApp || currentApp.windowCount !== pendingApp.windowCount
        || !AppDeckModel.forceKillScopeMatches(
          currentApp, pendingApp.forceKillScope)) {
      message = "Kill target changed. Review it again."
      settled()
      return
    }
    if (!AppDeckModel.forceKillScopeIsExclusive(currentApp, selection.allApps)) {
      message = "Kill target is shared with another Running App."
      settled()
      return
    }
    if (!targets.length)
      message = "No valid Kill targets."
    else if (!desktop.killAvailable)
      message = "Unable to send Kill request."
    else {
      kill.forceKillResponseCount = 0
      kill.forceKillFailureCount = 0
      kill.forceKillRequests = targets
    }
    settled()
  }

  function recordForceKillResponse(succeeded) {
    if (!kill.forceKillRequests.length) return
    kill.forceKillResponseCount++
    if (!succeeded) kill.forceKillFailureCount++
    if (kill.forceKillResponseCount < kill.forceKillRequests.length) return

    var requestCount = kill.forceKillRequests.length
    var failures = kill.forceKillFailureCount
    kill.forceKillRequests = []
    if (failures === requestCount)
      message = "Unable to send Kill request."
    else if (failures)
      message = "Some Kill requests could not be sent."
    else
      message = "Kill requested for " + requestCount
        + (requestCount === 1 ? " owner." : " owners.")
    settled()
  }

  function cancelReview() { pendingForceKillApp = null }

  Instantiator {
    model: kill.forceKillRequests
    delegate: QtObject {
      id: delivery
      required property string modelData
      property var request: null
      property bool finished: false
      function complete(succeeded) {
        if (finished) return
        finished = true
        // Defer aggregation: finishing the batch destroys its request objects.
        Qt.callLater(function() { kill.recordForceKillResponse(succeeded) })
      }
      Component.onCompleted: {
        request = desktop.killRequest.createObject(delivery, { command: modelData })
        if (!request) { complete(false); return }
        request.completed.connect(delivery.complete)
        request.start()
      }
      Component.onDestruction: { if (request) request.destroy() }
    }
  }
}
