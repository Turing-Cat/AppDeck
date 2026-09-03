function normalizedAppId(value) {
  return String(value || "").trim().toLowerCase();
}

function ownerSnapshot(snapshots, index, seen) {
  var snapshot = snapshots[index];
  if (!snapshot.parent || seen[index]) return snapshot;

  seen[index] = true;
  for (var i = 0; i < snapshots.length; i++) {
    if (snapshots[i] === snapshot.parent || snapshots[i].handle === snapshot.parent)
      return ownerSnapshot(snapshots, i, seen);
  }
  return snapshot;
}

function runningApps(snapshots, desktopEntryLookup) {
  var groups = [];
  var groupsByIdentity = Object.create(null);

  for (var i = 0; i < snapshots.length; i++) {
    var owner = ownerSnapshot(snapshots, i, {});
    var normalized = normalizedAppId(owner.appId);
    var ownerIndex = snapshots.indexOf(owner);
    var identity = normalized
      ? "app:" + normalized
      : "unknown:" + String(owner.id || ownerIndex);
    var group = groupsByIdentity[identity];
    if (!group) {
      var appId = String(owner.appId || "").trim();
      var entry = appId && desktopEntryLookup ? desktopEntryLookup(appId) : null;
      group = {
        identity: identity,
        appId: appId,
        name: String((entry && entry.name) || appId || owner.title || "Unidentified App"),
        icon: String((entry && entry.icon) || "application-x-executable"),
        windowCount: 0,
        workspaces: [],
        currentTitle: "",
        windows: []
      };
      groupsByIdentity[identity] = group;
      groups.push(group);
    }
    group.windowCount++;
    group.windows.push(snapshots[i]);

    var workspace = String(snapshots[i].workspace || "").trim();
    if (workspace && group.workspaces.indexOf(workspace) === -1)
      group.workspaces.push(workspace);

    var title = String(snapshots[i].title || "").trim();
    if (title && (snapshots[i].activated || !group.currentTitle))
      group.currentTitle = title;
  }

  return groups;
}

function reconcileSelectedIdentity(previousIdentity, previousIndex, apps) {
  if (!apps.length) return "";

  for (var i = 0; i < apps.length; i++) {
    if (apps[i].identity === previousIdentity) return previousIdentity;
  }

  var index = Number(previousIndex);
  if (!isFinite(index)) index = 0;
  index = Math.max(0, Math.min(apps.length - 1, Math.floor(index)));
  return apps[index].identity;
}

if (typeof module !== "undefined") {
  module.exports = {
    runningApps: runningApps,
    reconcileSelectedIdentity: reconcileSelectedIdentity
  };
}
