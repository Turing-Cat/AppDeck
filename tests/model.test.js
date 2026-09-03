"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const { runningApps, reconcileSelectedIdentity } = require("../ProcDeckModel.js");

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
