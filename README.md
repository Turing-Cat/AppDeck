# ProcDeck

ProcDeck is a keyboard-first application finder, starter, switcher, and closer for
Omarchy 4. It manages running GUI applications as groups of windows instead of
exposing a raw process table.

Status: ProcDeck v0.2 is implemented and verified as of 2026-09-07.

## v0.2 scope

ProcDeck opens instantly and presents installed and running GUI apps in one list.

Included:

- A fullscreen Omarchy shell overlay summoned with `ALT + SPACE`.
- One row per application, grouping windows by normalized Wayland `appId` and
  assigning an explicit child dialog to its parent's application.
- Application name and icon resolved from the matching desktop entry, with
  readable fallbacks when no entry exists.
- Fuzzy search every visible app by its displayed name, using exact, prefix,
  substring, and ordered-character matches.
- Start a selected launchable app through Omarchy's shared application library.
- Window count and workspace list for every application.
- Most-recently-used ordering, with the active application first.
- The previous application initially selected, so opening ProcDeck and pressing
  Enter switches back immediately.
- Focus the most recently used window in the selected application.
- Gracefully close every window in the selected application.
- Kill the selected application's exact Hyprland window owners after an
  explicit confirmation.
- Live updates as windows open, close, move, or change title.
- Mouse support alongside the complete keyboard flow.

Explicitly deferred:

- CPU, memory, disk, network, PID trees, and other system-monitor features.
- Background polling.
- Per-window expansion, window previews, history, favourites, settings UI,
  custom grouping rules, arbitrary command execution, and launch arguments.
- Support for compositors other than Hyprland.

Resource metrics are intentionally out of v0.2. A Wayland application group
does not map reliably to one Linux process tree: browsers, Electron apps,
portals, and sandboxed apps all break that assumption in different ways. Add
metrics only after a measured need and a documented grouping policy.

## Interaction contract

| Input | Result |
| --- | --- |
| Type | Fuzzy-filter all apps by displayed name |
| `Up` / `Down` | Move selection |
| `Page Up` / `Page Down` | Move by a page |
| `Home` / `End` | Jump to first / last result |
| `Enter` or row click | Focus a Running App or Start Running a Launchable App |
| `Delete` | Gracefully close all windows in the selected Running App |
| `Shift + Delete` | Open the selected Running App's Kill confirmation |
| `Escape` | Clear a non-empty search; otherwise close ProcDeck |

The Kill confirmation names the application and window count. `Enter`
confirms; `Escape` cancels and returns focus to the list. A failed action must
leave the overlay usable and show a short inline footer error. ProcDeck never
requests elevated privileges.

When an installed application gains or loses its last app window, its row stays
selected and changes state. A disappearing result moves selection to the nearest
row. Closing the last result shows an empty state instead of dismissing the
overlay.

## UI contract

The [interactive v0.1 mockup](docs/mockups/procdeck-v01.html) remains a baseline
for the responsive layout; it does not include launchable search results.

The overlay reuses Omarchy's shared `Color`, `Style`, `BorderSurface`, and
`ConfirmDialog` primitives. It contains only four regions:

1. A search/header row plus the current running-app and window totals.
2. A single application list. Running rows show window and workspace details;
   launchable rows state that the app is not running and can be started.
3. A compact bottom detail/action area for the selected application: icon,
   identity, state, and the actions available for its kind.
4. A footer with the keyboard hints.

The application list fills the available body height and the detail area grows
only to fit its content. A Running App shows Focus, Close, and Kill; a Launchable
App shows only Start Running. At narrow widths, the action group wraps below its
scope label. The selected row uses the shell's existing selected-state colours;
Kill alone uses the urgent colour. ProcDeck owns no theme palette.

## Data and action model

ProcDeck uses the native objects already maintained by the long-running shell:

```text
Hyprland.toplevels
  -> keep live, uniquely addressed Wayland windows
  -> normalize and group by Wayland appId
  -> enrich with DesktopEntries.heuristicLookup(appId)
  -> filter and sort in a pure JavaScript model
  -> render the QML list

DesktopEntries.applications
  -> keep visible installed desktop applications
  -> merge entries with matching Running Apps
  -> keep unmatched entries as Launchable Apps
  -> fuzzy-rank the unified list by displayed name
```

Actions stay within APIs supplied by Hyprland, Quickshell, and the Omarchy shell:

- Focus first releases the overlay's exclusive keyboard focus, then asks
  Hyprland to focus the group's most recently active window by exact address.
- Close calls `Toplevel.close()` on each window in the group.
- Kill asks Hyprland to immediately end the exact window owners belonging to the
  selected app. It does not infer a process tree or use name-based `pkill`.
- Start Running delegates the selected desktop entry to Omarchy's shared application
  library, falling back to `DesktopEntry.execute()` when the service is absent.

If `appId` is empty and the window has no identified parent, ProcDeck keeps that
window as its own group. It must not merge unrelated unknown windows just
because their titles happen to match. The overlay itself is a layer surface,
not a toplevel, so it is naturally excluded from the list.

Application presentation resolves in this order: desktop-entry name and icon,
reported `appId`, then window title and a generic icon. Presentation metadata
never changes application identity.

## Plugin contract

The plugin id is `procdeck.app`. It is an `overlay` with `keepLoaded: true` so
opening is warm and the in-memory MRU order can be maintained for the whole
shell session. The entry component exposes `open(payloadJson)`, `close()`, and
`toggle()` for the Omarchy shell host.

The smallest complete repository is:

```text
ProcDeck/
├── manifest.json          # Omarchy schema v1; overlay entry point
├── ProcDeck.qml           # Window, keyboard flow, and actions
├── ProcDeckModel.js       # Pure grouping, search, and sorting logic
├── tests/
│   └── model.test.js      # One dependency-free Node self-check
├── README.md
└── LICENSE
```

No package manager, build step, daemon, helper service, install hook, assets
directory, or component hierarchy is needed for v0.2. A marketplace preview
image can be added only when the UI is stable.

MRU state lives only for the current `omarchy-shell` session and is not written
to disk. An empty query shows Running Apps in activity order followed by
Launchable Apps in name order. A non-empty query uses case-insensitive,
space-separated terms against displayed names and ranks exact, prefix,
substring, then ordered-character matches. Input changes select the highest
ranked result; desktop updates preserve the selected application whenever it
still exists.

The intended manifest is:

```json
{
  "schemaVersion": 1,
  "id": "procdeck.app",
  "name": "ProcDeck",
  "version": "0.2.0",
  "description": "Find, start, focus, close, or force-kill GUI applications",
  "kinds": ["overlay"],
  "keepLoaded": true,
  "entryPoints": { "overlay": "ProcDeck.qml" }
}
```

The user-owned shortcut is deliberately separate from plugin installation:

```lua
o.bind(
  "ALT + SPACE",
  "ProcDeck",
  "omarchy-shell shell toggle procdeck.app"
)
```

This avoids taking over Omarchy's existing `SUPER + CTRL + T` Activity/btop
binding.

## Local development

Omarchy 4.0.2 has no command for linking an individual plugin. During local
development, link this checkout into the user plugin directory:

```bash
ln -s /home/zjh/Projects/ProcDeck ~/.config/omarchy/plugins/procdeck.app
```

The shell discovers a linked plugin, but recursive file watching does not
follow the linked directory. Validate the real checkout and explicitly rescan
after changes:

```bash
cd /home/zjh/Projects/ProcDeck
omarchy plugin validate .
omarchy-shell shell rescanPlugins
omarchy-shell shell toggle procdeck.app
```

Enable it once with `omarchy plugin enable procdeck.app`. These user-config
changes are performed only after separate approval.

## Repository verification

The repository-contained v0.2 passes 26 dependency-free Node model tests,
Omarchy 4.0.2 plugin validation, QML formatting/parsing, and `qmllint` against
the installed Quickshell 0.3.1 and Hyprland 0.56.2 APIs.

The enabled development plugin was reloaded by restarting Omarchy Shell. A live
Pinta smoke test verified fuzzy matching with `pta`, Start Running, automatic
transition to the running Focus / Close / Kill controls, Close, and the return
to Start Running. The broader multi-window and multi-monitor matrix remains an
acceptance check.

## v0.2 acceptance checks

- Ten windows with four app IDs render as four application rows.
- Empty search includes running and launchable apps; fuzzy search uses displayed
  names and ranks all matching states together.
- Running Apps show Focus, Close, and Kill. Launchable Apps show only Start
  Running and cannot receive Close or Kill actions.
- Selection follows an installed app through running-state changes.
- The active app is first; subsequent focus changes update MRU order without
  polling.
- Focus closes the overlay and activates the expected window.
- Close sends a graceful close request to every window in only that app group.
- Kill cannot run without confirmation and targets each unique positive
  window owner only through its exact Hyprland window identity.
- Empty `appId` windows remain separate.
- Selection remains valid when filtering or when a selected window disappears.
- Empty and no-match states are distinct.
- `omarchy plugin validate .` passes on the supported Omarchy release.
- The QML entry point loads without warnings.
- A separately approved manual smoke matrix remains for a multi-window browser,
  an Electron app, a native app, an unidentified window, a save dialog,
  multiple workspaces, and multiple monitors.

## Reference baseline

The design is based on the Omarchy 4 shell plugin contract and the APIs present
on the development machine: Omarchy 4.0.2, Quickshell 0.3.1, and Hyprland
0.56.2.

- [Omarchy shell plugins](https://omarchy.org/manual/shell-plugins/)
- [Quickshell Toplevel](https://quickshell.org/docs/types/Quickshell.Wayland/Toplevel/)
- [Quickshell ToplevelManager](https://quickshell.org/docs/v0.3.0/types/Quickshell.Wayland/ToplevelManager/)
- [Quickshell Hyprland integration](https://quickshell.org/docs/v0.3.1/types/Quickshell.Hyprland/Hyprland/)
