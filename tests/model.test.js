"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  runningApps,
  filterRunningApps,
  orderRunningApps,
  initialSelectedIdentity,
  mostRecentlyActiveAppWindow,
  gracefulCloseTargets,
  forceKillTargets,
  pageSelectionIndex,
  reconcileSelectedIdentity
} = require("../ProcDeckModel.js");

test("ten App Windows with four normalized identities form four Running Apps", () => {
  const snapshots = [
    " org.browser ", "ORG.BROWSER", "org.browser",
    "com.editor", "com.editor", "com.editor",
    "org.chat", "org.chat",
    "org.terminal", "org.terminal"
  ].map((appId, index) => ({ id: String(index), appId }));

  const apps = runningApps(snapshots, () => null);

  assert.deepEqual(
    apps.map(app => [app.identity, app.windowCount]),
    [
      ["app:org.browser", 3],
      ["app:com.editor", 3],
      ["app:org.chat", 2],
      ["app:org.terminal", 2]
    ]
  );
});

test("a Dialog Window uses its parent App Window identity", () => {
  const parent = {};
  const dialog = {};
  const apps = runningApps([
    { id: "parent", handle: parent, appId: "org.editor", title: "Document" },
    { id: "dialog", handle: dialog, parent, appId: "org.portal", title: "Save As" }
  ], () => null);

  assert.deepEqual(
    apps.map(app => [app.identity, app.windowCount]),
    [["app:org.editor", 2]]
  );
});

test("each Unidentified App Window remains its own Running App", () => {
  const apps = runningApps([
    { id: "mystery-1", appId: "", title: "Untitled" },
    { id: "mystery-2", appId: "", title: "Untitled" }
  ], () => null);

  assert.deepEqual(
    apps.map(app => [app.identity, app.windowCount]),
    [
      ["unknown:mystery-1", 1],
      ["unknown:mystery-2", 1]
    ]
  );
});

test("presentation metadata enriches records without changing Running App identity", () => {
  const entries = {
    "org.browser": { id: "browser.desktop", name: "Web Browser", icon: "web-browser" }
  };
  const apps = runningApps([
    { id: "browser-1", appId: "org.browser", title: "Start", workspace: "1" },
    { id: "browser-2", appId: "org.browser", title: "Downloads", workspace: "2", activated: true },
    { id: "terminal", appId: "Org.Terminal", title: "Shell", workspace: "2" },
    { id: "mystery", appId: "", title: "Mystery Window", workspace: "3" }
  ], appId => entries[appId.toLowerCase()] || null);

  assert.deepEqual(
    apps.map(app => ({
      identity: app.identity,
      appId: app.appId,
      name: app.name,
      icon: app.icon,
      windowCount: app.windowCount,
      workspaces: app.workspaces,
      currentTitle: app.currentTitle
    })),
    [
      {
        identity: "app:org.browser",
        appId: "org.browser",
        name: "Web Browser",
        icon: "web-browser",
        windowCount: 2,
        workspaces: ["1", "2"],
        currentTitle: "Downloads"
      },
      {
        identity: "app:org.terminal",
        appId: "Org.Terminal",
        name: "Org.Terminal",
        icon: "application-x-executable",
        windowCount: 1,
        workspaces: ["2"],
        currentTitle: "Shell"
      },
      {
        identity: "unknown:mystery",
        appId: "",
        name: "Mystery Window",
        icon: "application-x-executable",
        windowCount: 1,
        workspaces: ["3"],
        currentTitle: "Mystery Window"
      }
    ]
  );
});

test("live updates preserve the Selected App or choose the nearest remaining row", () => {
  const app = identity => ({ identity });

  assert.equal(
    reconcileSelectedIdentity("app:editor", 1, [
      app("app:new"), app("app:browser"), app("app:editor")
    ]),
    "app:editor"
  );
  assert.equal(
    reconcileSelectedIdentity("app:editor", 1, [app("app:browser"), app("app:chat")]),
    "app:chat"
  );
  assert.equal(reconcileSelectedIdentity("", -1, [app("app:browser")]), "app:browser");
  assert.equal(reconcileSelectedIdentity("app:browser", 0, []), "");
});

test("a Search Query matches every term across Running App fields", () => {
  const apps = runningApps([
    { id: "browser", appId: "org.browser", title: "Release Notes" },
    { id: "editor", appId: "com.editor", title: "ProcDeck README" },
    { id: "chat", appId: "org.chat", title: "Team Room" }
  ], appId => appId === "org.browser"
    ? { name: "Web Browser", icon: "web-browser" }
    : null);

  assert.deepEqual([
    filterRunningApps(apps, "WEB").map(app => app.identity),
    filterRunningApps(apps, "com.editor").map(app => app.identity),
    filterRunningApps(apps, "release").map(app => app.identity),
    filterRunningApps(apps, "  web   notes ").map(app => app.identity),
    filterRunningApps(apps, "web procdeck").map(app => app.identity)
  ], [
    ["app:org.browser"],
    ["app:com.editor"],
    ["app:org.browser"],
    ["app:org.browser"],
    []
  ]);
});

test("Activity Order uses the startup seed then follows live Active App changes", () => {
  const startup = orderRunningApps(runningApps([
    { id: "editor", appId: "editor", focusHistoryId: 2 },
    { id: "browser", appId: "browser", activated: true, focusHistoryId: 0 },
    { id: "chat", appId: "chat", focusHistoryId: 1 }
  ], () => null), []);
  const live = orderRunningApps(runningApps([
    { id: "new", appId: "new", focusHistoryId: 0 },
    { id: "editor", appId: "editor", focusHistoryId: 0 },
    { id: "browser", appId: "browser", focusHistoryId: 0 },
    { id: "chat", appId: "chat", activated: true, focusHistoryId: 9 }
  ], () => null), startup.map(item => item.identity));

  assert.deepEqual([
    startup.map(item => item.identity),
    live.map(item => item.identity)
  ], [
    ["app:browser", "app:chat", "app:editor"],
    ["app:chat", "app:browser", "app:editor", "app:new"]
  ]);
});

test("opening selects the Previous App when it exists", () => {
  const app = (identity, activated = false) => ({ identity, activated });

  assert.deepEqual([
    initialSelectedIdentity([app("app:active", true), app("app:previous"), app("app:older")]),
    initialSelectedIdentity([app("app:recent"), app("app:older")]),
    initialSelectedIdentity([app("app:only")]),
    initialSelectedIdentity([])
  ], ["app:previous", "app:recent", "app:only", ""]);
});

test("focus selects the most recently active App Window within the Selected App", () => {
  const selectedOlder = {
    id: "selected-older", appId: "org.selected", focusHistoryId: 7
  };
  const selectedRecent = {
    id: "selected-recent", appId: "org.selected", focusHistoryId: 2
  };
  const globallyNewer = {
    id: "other-newest", appId: "org.other", focusHistoryId: 0, activated: true
  };
  const apps = runningApps([
    selectedOlder, globallyNewer, selectedRecent
  ], () => null);
  const selectedApp = apps.find(app => app.identity === "app:org.selected");
  const activated = { id: "activated", activated: true, focusHistoryId: 9 };
  const rankedNewer = { id: "ranked-newer", focusHistoryId: 0 };
  const single = { id: "single" };

  assert.deepEqual([
    mostRecentlyActiveAppWindow(selectedApp),
    mostRecentlyActiveAppWindow({ windows: [rankedNewer, activated] }),
    mostRecentlyActiveAppWindow({ windows: [single] }),
    mostRecentlyActiveAppWindow({ windows: [
      { id: "missing" },
      { id: "negative", focusHistoryId: -1 },
      { id: "invalid", focusHistoryId: "unknown" }
    ] }),
    mostRecentlyActiveAppWindow({ windows: [
      { id: "tied-a", focusHistoryId: 3 },
      { id: "tied-b", focusHistoryId: "3" }
    ] }),
    mostRecentlyActiveAppWindow({ windows: [] })
  ], [selectedRecent, activated, single, null, null, null]);
});

test("Graceful Close targets every App Window in the Selected App and no others", () => {
  const selectedFirst = { id: "selected-first", appId: "org.selected" };
  const outside = { id: "outside", appId: "org.other" };
  const selectedSecond = { id: "selected-second", appId: "org.selected" };
  const apps = runningApps([selectedFirst, outside, selectedSecond], () => null);
  const selectedApp = apps.find(app => app.identity === "app:org.selected");

  assert.deepEqual(gracefulCloseTargets(selectedApp), [selectedFirst, selectedSecond]);
});

test("Force Kill produces no targets without confirmation", () => {
  const selectedApp = {
    windows: [{ ownerIdentity: 41, hyprlandAddress: "0xabc" }]
  };

  assert.deepEqual(forceKillTargets(selectedApp, false), []);
});

test("confirmed Force Kill targets each valid Selected App owner exactly once", () => {
  const selectedWindows = [
    { id: "selected-first", appId: "org.selected", ownerIdentity: 41, hyprlandAddress: "0xa1" },
    { id: "selected-duplicate", appId: "org.selected", ownerIdentity: 41, hyprlandAddress: "0xa2" },
    { id: "selected-second", appId: "org.selected", ownerIdentity: 82, hyprlandAddress: "0xB3" },
    { id: "missing-owner", appId: "org.selected", hyprlandAddress: "0xc4" },
    { id: "zero-owner", appId: "org.selected", ownerIdentity: 0, hyprlandAddress: "0xd5" },
    { id: "negative-owner", appId: "org.selected", ownerIdentity: -3, hyprlandAddress: "0xe6" },
    { id: "fractional-owner", appId: "org.selected", ownerIdentity: 4.5, hyprlandAddress: "0xf7" },
    { id: "non-numeric-owner", appId: "org.selected", ownerIdentity: "unknown", hyprlandAddress: "0x18" },
    { id: "boolean-owner", appId: "org.selected", ownerIdentity: true, hyprlandAddress: "0x19" },
    { id: "hex-string-owner", appId: "org.selected", ownerIdentity: "0x2a", hyprlandAddress: "0x20" },
    { id: "invalid-address", appId: "org.selected", ownerIdentity: 99, hyprlandAddress: "title:.*" }
  ];
  const outside = {
    id: "outside", appId: "org.other", ownerIdentity: 123, hyprlandAddress: "0x999"
  };
  const apps = runningApps([selectedWindows[0], outside].concat(selectedWindows.slice(1)), () => null);
  const selectedApp = apps.find(app => app.identity === "app:org.selected");

  assert.deepEqual(forceKillTargets(selectedApp, true), [
    'hl.dsp.window.kill({ window = "address:0xa1" })',
    'hl.dsp.window.kill({ window = "address:0xB3" })'
  ]);
});

test("Page movement uses the visible page size and stops at result boundaries", () => {
  assert.deepEqual([
    pageSelectionIndex(0, 5, 6, 1),
    pageSelectionIndex(4, 5, 6, -1),
    pageSelectionIndex(1, 10, 4, 1),
    pageSelectionIndex(8, 10, 4, 1),
    pageSelectionIndex(2, 10, 4, -1),
    pageSelectionIndex(0, 0, 4, 1)
  ], [4, 0, 5, 9, 0, -1]);
});
