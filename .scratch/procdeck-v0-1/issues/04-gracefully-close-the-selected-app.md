# 04: Gracefully Close the Selected App

**What to build:** Let a user request normal application-controlled shutdown for every App Window in the Selected App while keeping ProcDeck stable as those windows disappear.

**Blocked by:** 02: Find and stably select a Running App.

**Status:** ready-for-agent

- [ ] Delete and the visible Close action send a Graceful Close request to every App Window in the Selected App.
- [ ] Graceful Close does not require confirmation and uses each App Window's native close capability instead of a shell command.
- [ ] No App Window outside the Selected App receives a Close Request.
- [ ] The UI describes the result as a Close Request and does not claim that the application exited or accepted it.
- [ ] As App Windows disappear, the list updates live and preserves or reconciles the Selected App according to the selection contract.
- [ ] Closing the final Running App shows the empty state instead of dismissing ProcDeck.
- [ ] A failed request leaves ProcDeck usable and displays a short inline footer error.
- [ ] Observable checks verify complete and exclusive action scope for a multi-window Running App.
