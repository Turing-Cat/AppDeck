import QtQuick
import Quickshell.Io
import "AppDeckModel.js" as AppDeckModel

Socket {
  id: forceKillSocket
  required property string command
  signal completed(bool succeeded)
  property bool finished: false
  property bool requestWritten: false
  property string responseBuffer: ""
  property Timer responseTimeout: Timer {
    interval: 1500
    running: false
    repeat: false
    onTriggered: forceKillSocket.acceptResponse("", true)
  }

  connected: false

  function start() { responseTimeout.start(); connected = true }

  function acceptResponse(chunk, ended) {
    if (finished) return
    var state = AppDeckModel.forceKillResponseState(
      responseBuffer, chunk, ended)
    responseBuffer = state.response
    if (state.done) finish(state.succeeded)
  }

  function finish(succeeded) {
    if (finished) return
    finished = true
    responseTimeout.stop()
    connected = false
    completed(succeeded)
  }

  onConnectionStateChanged: {
    if (finished) return
    if (connected) {
      requestWritten = true
      write("dispatch " + command)
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
