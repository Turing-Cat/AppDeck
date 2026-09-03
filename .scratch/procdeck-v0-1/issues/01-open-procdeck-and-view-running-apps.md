# 01: Open ProcDeck and view Running Apps

**What to build:** Deliver a warm Omarchy overlay that a user can open to see the desktop's current Running Apps as live, readable rows and dismiss without affecting any App Window.

**Blocked by:** None (can start immediately).

**Status:** resolved

- [x] The `procdeck.app` plugin is an overlay that stays loaded and exposes open, close, and toggle lifecycle operations to the shell host.
- [x] Opening ProcDeck derives Running Apps from the shell's live desktop window objects without a daemon, helper process, process-table scan, or background polling.
- [x] App Windows with the same reported application identity form one Running App, while an explicit Dialog Window belongs to its parent's Running App.
- [x] Ten App Windows carrying four application identities render as four Running App rows.
- [x] Each Unidentified App Window remains its own Running App and is never grouped by title alone.
- [x] Desktop-entry metadata supplies presentation name and icon without changing identity; missing metadata falls back to reported identity, then window title and a generic icon.
- [x] Every row exposes the Running App name, icon, window count, and workspace labels, with selected details showing the current title and reported identity.
- [x] The layout uses the Omarchy shell's shared styling primitives and moves the selected details below the list at narrow widths.
- [x] Escape dismisses ProcDeck when no Search Query is present, and the overlay itself never appears as a Running App.
- [x] A dependency-free model self-check covers grouping, Dialog Window ownership, presentation fallback, and Unidentified App behavior through observable results.

## Answer

ProcDeck now has a schema-v1, keep-loaded Omarchy overlay that derives and presents live Running Apps using the installed Hyprland, Quickshell, and shared shell UI APIs. The pure model self-check and repository plugin validator pass. User configuration, plugin enablement, and live desktop smoke testing remain deferred to their separately authorized stage.
