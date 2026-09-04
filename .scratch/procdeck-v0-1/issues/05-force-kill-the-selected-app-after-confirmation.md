# 05: Force Kill the Selected App after confirmation

**What to build:** Let a user deliberately Force Kill only the Selected App after reviewing an explicit confirmation that names the target and its scope.

**Blocked by:** 02: Find and stably select a Running App.

**Status:** resolved

- [x] Shift+Delete and the urgent Force Kill action open a confirmation naming the Selected App and its App Window count.
- [x] Enter confirms from the dialog; Escape cancels and returns keyboard focus to the Running App list.
- [x] Cancellation performs no destructive action.
- [x] Confirmation targets each unique positive desktop-reported window owner belonging to the Selected App through its exact Hyprland window identity.
- [x] Force Kill never infers a PID tree, matches a process by name, targets another Running App, or requests elevated privileges.
- [x] Duplicate owner identities are acted on only once, and absent or invalid owner identities are ignored safely.
- [x] A failed Force Kill leaves ProcDeck usable and displays a short inline footer error.
- [x] Observable checks verify the confirmation gate, deduplication, invalid-owner handling, and exclusive action scope.

## Answer

Shift+Delete and the urgent Force Kill action now open the shared confirmation dialog with a frozen Running App identity, name, and App Window count. Cancellation produces no targets; confirmation revalidates the live Running App and scope, then sends one Hyprland 0.56 Lua kill dispatcher per unique positive numeric window owner through its exact validated address. Native IPC responses are checked before ProcDeck reports the request, while invalid owners, changed targets, socket errors, and compositor rejections leave the overlay usable with an inline footer error. Thirteen dependency-free behavior checks, plugin validation, QML parsing/linting, and diff checks pass.
