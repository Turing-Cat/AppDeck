# 04: Gracefully Close the Selected App

**What to build:** Let a user request normal application-controlled shutdown for every App Window in the Selected App while keeping AppDeck stable as those windows disappear.

**Blocked by:** 02: Find and stably select a Running App.

**Status:** resolved

- [x] Delete and the visible Close action send a Graceful Close request to every App Window in the Selected App.
- [x] Graceful Close does not require confirmation and uses each App Window's native close capability instead of a shell command.
- [x] No App Window outside the Selected App receives a Close Request.
- [x] The UI describes the result as a Close Request and does not claim that the application exited or accepted it.
- [x] As App Windows disappear, the list updates live and preserves or reconciles the Selected App according to the selection contract.
- [x] Closing the final Running App shows the empty state instead of dismissing AppDeck.
- [x] A failed request leaves AppDeck usable and displays a short inline footer error.
- [x] Observable checks verify complete and exclusive action scope for a multi-window Running App.

## Answer

Delete and the visible Close action now share one Graceful Close boundary that sends each App Window in the Selected App a native `Toplevel.close()` request without confirmation or shell commands. AppDeck continues across missing or failed targets, remains open, reports only that a Close Request was sent, and uses the existing live update and selection contract as windows disappear through the final empty state. Eleven dependency-free model checks, plugin validation, QML parsing/linting, and diff checks pass.
