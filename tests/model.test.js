"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {
  runningApps,
  filterRunningApps,
  orderRunningApps,
  initialSelectedIdentity,
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
