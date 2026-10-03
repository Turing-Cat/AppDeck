import QtQuick
import "AppDeckModel.js" as AppDeckModel

QtObject {
  id: selection
  property var entries: []
  signal resultsChanged()
  signal windowChosen()
  signal windowUnavailable()
  property var allApps: []
  property var apps: []
  property var activityOrderIdentities: []
  property string searchQuery: ""
  property string selectedIdentity: ""
  property string selectedWindowAppIdentity: ""
  property string selectedWindowId: ""
  readonly property int selectedIndex: {
    for (var i = 0; i < apps.length; i++)
      if (apps[i].identity === selectedIdentity) return i
    return -1
  }
  readonly property var selectedApp: selectedIndex >= 0 && selectedIndex < apps.length
    ? apps[selectedIndex] : null
  readonly property bool windowSelectionActive: selectedWindowId !== ""
    && selectedWindowAppIdentity === selectedIdentity
  readonly property var selectedWindow: windowSelectionActive
    ? selection.windowById(selectedWindowId) : null

  onSelectedIdentityChanged: clearWindowSelection()
  onAppsChanged: reconcileWindowSelection()

  function updateSearchResults(previousSelection, previousIndex, preserveSelection) {
    selection.apps = AppDeckModel.searchResults(
      selection.allApps, entries, selection.searchQuery)
    selection.selectedIdentity = preserveSelection
      ? AppDeckModel.reconcileSelectedIdentity(previousSelection, previousIndex, selection.apps)
      : selection.apps.length ? selection.apps[0].identity : ""
    resultsChanged()
  }

  function clearWindowSelection() {
    selection.selectedWindowId = ""
    selection.selectedWindowAppIdentity = ""
  }

  function windowById(id) {
    var app = null
    for (var a = 0; a < selection.apps.length; a++)
      if (selection.apps[a].identity === selection.selectedIdentity) app = selection.apps[a]
    if (!app || app.kind !== "running") return null
    for (var i = 0; i < app.windows.length; i++)
      if (app.windows[i].id === id) return app.windows[i]
    return null
  }

  function selectWindow(delta) {
    var app = selection.selectedApp
    if (!app || app.kind !== "running" || !app.windows.length) return
    var index = -1
    if (selection.windowSelectionActive) {
      for (var i = 0; i < app.windows.length; i++)
        if (app.windows[i].id === selection.selectedWindowId) index = i
    }
    if (index < 0) {
      var recent = AppDeckModel.mostRecentlyActiveAppWindow(app)
      index = 0
      for (var j = 0; recent && j < app.windows.length; j++)
        if (app.windows[j].id === recent.id) index = j
    } else index = (index + delta + app.windows.length) % app.windows.length
    selection.selectedWindowAppIdentity = app.identity
    selection.selectedWindowId = app.windows[index].id
    windowChosen()
  }

  function reconcileWindowSelection() {
    if (!windowSelectionActive) return
    if (!windowById(selectedWindowId)) {
      clearWindowSelection()
      windowUnavailable()
    } else windowChosen()
  }

  function chooseWindow(id) {
    if (!windowById(id)) return
    selectedWindowAppIdentity = selectedIdentity
    selectedWindowId = id
    windowChosen()
  }

  function rebuild(snapshots, lookup) {
    var previousSelection = selectedApp
    var previousIndex = selectedIndex
    var grouped = AppDeckModel.runningApps(snapshots, lookup)
    var next = AppDeckModel.orderRunningApps(grouped, activityOrderIdentities)
    activityOrderIdentities = next.map(function(app) { return app.identity })
    allApps = next
    updateSearchResults(previousSelection, previousIndex, true)
  }

  function search(query) {
    clearWindowSelection()
    searchQuery = query
    updateSearchResults(null, 0, false)
  }

  function selectAbsolute(index) {
    clearWindowSelection()
    if (!apps.length) return
    index = Math.max(0, Math.min(index, apps.length - 1))
    selectedIdentity = apps[index].identity
    resultsChanged()
  }

  function select(delta) {
    clearWindowSelection()
    if (!apps.length) return
    var index = selectedIndex
    if (index < 0) index = delta < 0 ? apps.length - 1 : 0
    else index = ((index + delta) % apps.length + apps.length) % apps.length
    selectAbsolute(index)
  }
}
