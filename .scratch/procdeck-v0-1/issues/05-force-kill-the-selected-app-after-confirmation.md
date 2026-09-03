# 05: Force Kill the Selected App after confirmation

**What to build:** Let a user deliberately Force Kill only the Selected App after reviewing an explicit confirmation that names the target and its scope.

**Blocked by:** 02: Find and stably select a Running App.

**Status:** ready-for-agent

- [ ] Shift+Delete and the urgent Force Kill action open a confirmation naming the Selected App and its App Window count.
- [ ] Enter confirms from the dialog; Escape cancels and returns keyboard focus to the Running App list.
- [ ] Cancellation performs no destructive action.
- [ ] Confirmation targets each unique positive desktop-reported window owner belonging to the Selected App through its exact Hyprland window identity.
- [ ] Force Kill never infers a PID tree, matches a process by name, targets another Running App, or requests elevated privileges.
- [ ] Duplicate owner identities are acted on only once, and absent or invalid owner identities are ignored safely.
- [ ] A failed Force Kill leaves ProcDeck usable and displays a short inline footer error.
- [ ] Observable checks verify the confirmation gate, deduplication, invalid-owner handling, and exclusive action scope.
