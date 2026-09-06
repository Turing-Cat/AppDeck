function normalizedAppId(value) {
  return String(value || "").trim().toLowerCase();
}

function normalizedHyprlandAddress(value) {
  var address = String(value || "").trim().toLowerCase();
  if (/^[0-9a-f]+$/.test(address)) address = "0x" + address;
  return /^0x[0-9a-f]+$/.test(address) ? address : "";
}

function normalizedFocusHistoryId(value) {
  if (value === undefined || value === null || value === "") return null;
  var focusHistoryId = Number(value);
  return isFinite(focusHistoryId) && focusHistoryId >= 0 ? focusHistoryId : null;
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
  var seenAddresses = Object.create(null);
  var liveSnapshots = [];

  for (var snapshotIndex = 0; snapshotIndex < snapshots.length; snapshotIndex++) {
    var candidate = snapshots[snapshotIndex];
    if (!candidate || typeof candidate !== "object" || candidate.handle === null) continue;

    var hasAddress = candidate.hyprlandAddress !== undefined;
    var address = normalizedHyprlandAddress(candidate.hyprlandAddress);
    if (hasAddress && !address) continue;
    if (address && seenAddresses[address]) continue;
    if (address) seenAddresses[address] = true;
    liveSnapshots.push(candidate);
  }

  for (var i = 0; i < liveSnapshots.length; i++) {
    var owner = ownerSnapshot(liveSnapshots, i, {});
    var normalized = normalizedAppId(owner.appId);
    var ownerIndex = liveSnapshots.indexOf(owner);
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
        activated: false,
        focusHistoryId: null,
        windows: []
      };
      groupsByIdentity[identity] = group;
      groups.push(group);
    }
    group.windowCount++;
    group.windows.push(liveSnapshots[i]);

    var workspace = String(liveSnapshots[i].workspace || "").trim();
    if (workspace && group.workspaces.indexOf(workspace) === -1)
      group.workspaces.push(workspace);

    var title = String(liveSnapshots[i].title || "").trim();
    if (title && (liveSnapshots[i].activated || !group.currentTitle))
      group.currentTitle = title;

    if (liveSnapshots[i].activated === true) group.activated = true;
    var focusHistoryId = normalizedFocusHistoryId(liveSnapshots[i].focusHistoryId);
    if (focusHistoryId !== null
        && (group.focusHistoryId === null || focusHistoryId < group.focusHistoryId))
      group.focusHistoryId = focusHistoryId;
  }

  return groups;
}

function filterRunningApps(apps, query) {
  var terms = String(query || "").trim().toLowerCase().split(/\s+/).filter(Boolean);
  if (!terms.length) return apps;

  return apps.filter(function(app) {
    var searchable = [app.name, app.appId].concat(app.windows.map(function(window) {
      return window.title;
    })).join("\n").toLowerCase();
    return terms.every(function(term) { return searchable.indexOf(term) !== -1; });
  });
}

function orderRunningApps(apps, priorActivityOrder) {
  var priorOrder = priorActivityOrder || [];
  var activityOrderSeed = priorOrder.length ? priorOrder : apps.slice().sort(function(a, b) {
    var aRank = a.focusHistoryId === null ? Infinity : Number(a.focusHistoryId);
    var bRank = b.focusHistoryId === null ? Infinity : Number(b.focusHistoryId);
    return aRank === bRank ? apps.indexOf(a) - apps.indexOf(b) : aRank - bRank;
  }).map(function(app) { return app.identity; });
  var byIdentity = Object.create(null);
  var seen = Object.create(null);
  var ordered = [];

  apps.forEach(function(app) { byIdentity[app.identity] = app; });
  activityOrderSeed.concat(apps.map(function(app) { return app.identity; })).forEach(function(identity) {
    if (byIdentity[identity] && !seen[identity]) {
      seen[identity] = true;
      ordered.push(byIdentity[identity]);
    }
  });

  for (var i = 0; i < ordered.length; i++) {
    if (ordered[i].activated) {
      ordered.unshift(ordered.splice(i, 1)[0]);
      break;
    }
  }
  return ordered;
}

function initialSelectedIdentity(apps) {
  if (!apps.length) return "";
  return apps.length > 1 && apps[0].activated ? apps[1].identity : apps[0].identity;
}

function gracefulCloseTargets(runningApp) {
  return runningApp && Array.isArray(runningApp.windows)
    ? runningApp.windows.filter(function(window) { return window && typeof window === "object"; })
    : [];
}

function forceKillScope(runningApp) {
  var windows = gracefulCloseTargets(runningApp);
  var seenOwners = Object.create(null);
  var scope = [];
  for (var i = 0; i < windows.length; i++) {
    var owner = windows[i].ownerIdentity;
    var address = normalizedHyprlandAddress(windows[i].hyprlandAddress);
    if (typeof owner !== "number" || !isFinite(owner)
        || owner <= 0 || Math.floor(owner) !== owner
        || !address || seenOwners[owner])
      continue;

    seenOwners[owner] = true;
    scope.push({ ownerIdentity: owner, hyprlandAddress: address });
  }
  return scope.sort(function(a, b) {
    if (a.ownerIdentity !== b.ownerIdentity) return a.ownerIdentity - b.ownerIdentity;
    return a.hyprlandAddress < b.hyprlandAddress ? -1
      : a.hyprlandAddress > b.hyprlandAddress ? 1 : 0;
  });
}

function forceKillScopeMatches(runningApp, reviewedScope) {
  if (!Array.isArray(reviewedScope)) return false;
  var currentScope = forceKillScope(runningApp);
  if (currentScope.length !== reviewedScope.length) return false;
  for (var i = 0; i < currentScope.length; i++) {
    if (currentScope[i].ownerIdentity !== reviewedScope[i].ownerIdentity
        || currentScope[i].hyprlandAddress !== reviewedScope[i].hyprlandAddress)
      return false;
  }
  return true;
}

function forceKillScopeIsExclusive(runningApp, allApps) {
  if (!runningApp || !Array.isArray(allApps)) return false;
  var selectedOwners = Object.create(null);
  forceKillScope(runningApp).forEach(function(target) {
    selectedOwners["owner:" + target.ownerIdentity] = true;
  });

  for (var i = 0; i < allApps.length; i++) {
    var app = allApps[i];
    if (!app || app.identity === runningApp.identity) continue;
    var windows = gracefulCloseTargets(app);
    for (var j = 0; j < windows.length; j++) {
      if (selectedOwners["owner:" + windows[j].ownerIdentity]) return false;
    }
  }
  return true;
}

function forceKillTargets(runningApp, confirmed, allApps) {
  if (!confirmed) return [];
  if (Array.isArray(allApps) && !forceKillScopeIsExclusive(runningApp, allApps)) return [];
  return forceKillScope(runningApp).map(function(target) {
    return 'hl.dsp.window.kill({ window = "address:' + target.hyprlandAddress + '" })';
  });
}

function forceKillResponseState(response, chunk, ended) {
  var combined = String(response || "") + String(chunk || "");
  var succeeded = combined.trim() === "ok";
  return {
    response: combined,
    done: succeeded || ended === true,
    succeeded: succeeded
  };
}

function mostRecentlyActiveAppWindow(runningApp) {
  var windows = gracefulCloseTargets(runningApp);
  if (!windows.length) return null;

  for (var i = 0; i < windows.length; i++)
    if (windows[i].activated === true) return windows[i];
  if (windows.length === 1) return windows[0];

  var rankedWindow = null;
  var rankedFocusHistoryId = Infinity;
  var rankIsTied = false;
  for (var j = 0; j < windows.length; j++) {
    var focusHistoryId = normalizedFocusHistoryId(windows[j].focusHistoryId);
    if (focusHistoryId !== null && focusHistoryId < rankedFocusHistoryId) {
      rankedWindow = windows[j];
      rankedFocusHistoryId = focusHistoryId;
      rankIsTied = false;
    } else if (focusHistoryId !== null && focusHistoryId === rankedFocusHistoryId) {
      rankIsTied = true;
    }
  }
  return rankedWindow && !rankIsTied ? rankedWindow : null;
}

function focusCommand(window) {
  var address = normalizedHyprlandAddress(window && window.hyprlandAddress);
  return address
    ? 'hl.dsp.focus({ window = "address:' + address + '" })'
    : "";
}

function pageSelectionIndex(currentIndex, resultCount, pageSize, direction) {
  if (resultCount <= 0) return -1;
  var current = Math.max(0, Math.min(resultCount - 1, currentIndex));
  var page = Math.max(1, Math.floor(pageSize));
  return Math.max(0, Math.min(resultCount - 1, current + (direction < 0 ? -page : page)));
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
    normalizedHyprlandAddress: normalizedHyprlandAddress,
    runningApps: runningApps,
    filterRunningApps: filterRunningApps,
    orderRunningApps: orderRunningApps,
    initialSelectedIdentity: initialSelectedIdentity,
    mostRecentlyActiveAppWindow: mostRecentlyActiveAppWindow,
    focusCommand: focusCommand,
    gracefulCloseTargets: gracefulCloseTargets,
    forceKillScope: forceKillScope,
    forceKillScopeIsExclusive: forceKillScopeIsExclusive,
    forceKillScopeMatches: forceKillScopeMatches,
    forceKillTargets: forceKillTargets,
    forceKillResponseState: forceKillResponseState,
    pageSelectionIndex: pageSelectionIndex,
    reconcileSelectedIdentity: reconcileSelectedIdentity
  };
}
