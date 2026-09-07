function normalizedAppId(value) {
  return String(value || "").trim().toLowerCase();
}

function normalizedDesktopEntryId(value) {
  var id = normalizedAppId(value);
  return id.slice(-8) === ".desktop" ? id.slice(0, -8) : id;
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
        kind: "running",
        identity: identity,
        appId: appId,
        desktopEntryId: String((entry && entry.id) || ""),
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

function normalizedSearchText(value) {
  return String(value || "").trim().toLowerCase().replace(/\s+/g, " ");
}

function fuzzyTermScore(name, term) {
  if (name === term) return 400000 - name.length;
  if (name.indexOf(term) === 0) return 300000 - name.length;

  var substringIndex = name.indexOf(term);
  if (substringIndex !== -1)
    return 200000 - substringIndex * 100 - name.length;

  var bestGapCount = Infinity;
  var bestFirstIndex = Infinity;
  var firstIndex = name.indexOf(term.charAt(0));
  while (firstIndex !== -1) {
    var previousIndex = firstIndex;
    for (var i = 1; i < term.length; i++) {
      previousIndex = name.indexOf(term.charAt(i), previousIndex + 1);
      if (previousIndex === -1) break;
    }
    if (previousIndex !== -1) {
      var gapCount = previousIndex - firstIndex + 1 - term.length;
      if (gapCount < bestGapCount
          || (gapCount === bestGapCount && firstIndex < bestFirstIndex)) {
        bestGapCount = gapCount;
        bestFirstIndex = firstIndex;
      }
    }
    firstIndex = name.indexOf(term.charAt(0), firstIndex + 1);
  }

  return bestGapCount === Infinity ? -1
    : 100000 - bestGapCount * 100 - bestFirstIndex * 10 - name.length;
}

function fuzzyNameScore(name, query) {
  var normalizedName = normalizedSearchText(name);
  var normalizedQuery = normalizedSearchText(query);
  if (!normalizedQuery) return 0;

  var terms = normalizedQuery.split(" ");
  var score = 0;
  for (var i = 0; i < terms.length; i++) {
    var termScore = fuzzyTermScore(normalizedName, terms[i]);
    if (termScore < 0) return -1;
    score += termScore;
  }

  if (normalizedName === normalizedQuery) score += 4000000;
  else if (normalizedName.indexOf(normalizedQuery) === 0) score += 3000000;
  else if (normalizedName.indexOf(normalizedQuery) !== -1) score += 2000000;
  return score;
}

function runningAppForDesktopEntry(apps, desktopEntryId) {
  var id = normalizedDesktopEntryId(desktopEntryId);
  if (!id) return null;

  for (var i = 0; i < apps.length; i++) {
    if (apps[i].kind !== "launch"
        && (normalizedDesktopEntryId(apps[i].desktopEntryId) === id
          || normalizedDesktopEntryId(apps[i].appId) === id))
      return apps[i];
  }
  return null;
}

function searchResults(runningApps, desktopEntries, query) {
  var runningEntryIds = Object.create(null);
  var seenEntryIds = Object.create(null);
  var launchableApps = [];

  runningApps.forEach(function(app) {
    var entryId = normalizedDesktopEntryId(app.desktopEntryId);
    var appId = normalizedDesktopEntryId(app.appId);
    if (entryId) runningEntryIds[entryId] = true;
    if (appId) runningEntryIds[appId] = true;
  });

  (desktopEntries || []).forEach(function(entry) {
    var entryId = normalizedDesktopEntryId(entry && entry.id);
    var name = String((entry && entry.name) || (entry && entry.id) || "").trim();
    if (!entry || entry.noDisplay === true || !entryId || !name
        || runningEntryIds[entryId] || seenEntryIds[entryId])
      return;

    seenEntryIds[entryId] = true;
    launchableApps.push({
      kind: "launch",
      identity: "launch:" + entryId,
      appId: "",
      desktopEntryId: String(entry.id || "").trim(),
      desktopEntry: entry,
      name: name,
      icon: String(entry.icon || "application-x-executable"),
      windowCount: 0,
      workspaces: [],
      currentTitle: "",
      activated: false,
      focusHistoryId: null,
      windows: []
    });
  });

  launchableApps.sort(function(a, b) {
    var aName = a.name.toLowerCase();
    var bName = b.name.toLowerCase();
    if (aName !== bName) return aName < bName ? -1 : 1;
    return a.desktopEntryId < b.desktopEntryId ? -1
      : a.desktopEntryId > b.desktopEntryId ? 1 : 0;
  });

  var results = runningApps.concat(launchableApps);
  if (!normalizedSearchText(query)) return results;

  return results.map(function(app) {
    return { app: app, score: fuzzyNameScore(app.name, query) };
  }).filter(function(result) {
    return result.score >= 0;
  }).sort(function(a, b) {
    if (a.score !== b.score) return b.score - a.score;
    if (a.app.kind !== b.app.kind) return a.app.kind === "running" ? -1 : 1;
    var aName = normalizedSearchText(a.app.name);
    var bName = normalizedSearchText(b.app.name);
    if (aName !== bName) return aName < bName ? -1 : 1;
    return a.app.identity < b.app.identity ? -1
      : a.app.identity > b.app.identity ? 1 : 0;
  }).map(function(result) {
    return result.app;
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
  var runningApps = apps.filter(function(app) { return app.kind !== "launch"; });
  if (!runningApps.length) return apps[0].identity;
  return runningApps.length > 1 && runningApps[0].activated
    ? runningApps[1].identity : runningApps[0].identity;
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

function reconcileSelectedIdentity(previousSelection, previousIndex, apps) {
  if (!apps.length) return "";

  var previousIdentity = typeof previousSelection === "object" && previousSelection
    ? previousSelection.identity : String(previousSelection || "");

  for (var i = 0; i < apps.length; i++) {
    if (apps[i].identity === previousIdentity) return previousIdentity;
  }

  var previousEntryId = typeof previousSelection === "object" && previousSelection
    ? normalizedDesktopEntryId(previousSelection.desktopEntryId || previousSelection.appId)
    : previousIdentity.indexOf("launch:") === 0
      ? previousIdentity.slice(7) : "";
  if (previousEntryId) {
    for (var j = 0; j < apps.length; j++) {
      if (normalizedDesktopEntryId(apps[j].desktopEntryId || apps[j].appId)
          === previousEntryId)
        return apps[j].identity;
    }
  }

  var index = Number(previousIndex);
  if (!isFinite(index)) index = 0;
  index = Math.max(0, Math.min(apps.length - 1, Math.floor(index)));
  return apps[index].identity;
}

if (typeof module !== "undefined") {
  module.exports = {
    normalizedHyprlandAddress: normalizedHyprlandAddress,
    normalizedDesktopEntryId: normalizedDesktopEntryId,
    runningApps: runningApps,
    fuzzyNameScore: fuzzyNameScore,
    runningAppForDesktopEntry: runningAppForDesktopEntry,
    searchResults: searchResults,
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
