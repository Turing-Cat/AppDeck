# 02: Find and stably select a Running App

**What to build:** Let a keyboard-first user quickly find a Running App and keep a predictable Selected App while desktop state and the Search Query change.

**Blocked by:** 01: Open AppDeck and view Running Apps.

**Status:** resolved

- [x] Running Apps appear in Activity Order with the Active App first and the Previous App second.
- [x] Opening AppDeck initially selects the Previous App when it exists, allowing an immediate Enter action to switch back.
- [x] Focus changes update Activity Order from live desktop events without polling.
- [x] A Search Query matches application name, reported identity, and any grouped App Window title case-insensitively.
- [x] Space-separated search terms use AND semantics: every term must match at least one searchable field in the same Running App.
- [x] Typing filters the list, and Escape clears a non-empty Search Query before it can dismiss the overlay.
- [x] Up, Down, Page Up, Page Down, Home, and End move the Selected App according to the interaction contract; mouse selection is also supported.
- [x] Live updates preserve the Selected App while it still exists, and a newly appearing Running App never steals selection.
- [x] When the Selected App disappears, the nearest remaining visible row becomes selected; removing the final result produces an empty state without dismissing AppDeck.
- [x] An empty desktop and a Search Query with no matches have distinct visible states.
- [x] The dependency-free model self-check covers filtering, Activity Order, initial selection, and selection reconciliation through observable results.

## Answer

AppDeck now maintains an in-memory Activity Order from live Hyprland state, selects the Previous App on open when an Active App exists, and keeps selection stable across filtering and desktop updates. Keyboard and mouse navigation, viewport-aware page movement, case-insensitive AND search, and distinct empty states are implemented without polling or dependencies. Nine model behavior checks, plugin validation, QML parsing/linting, and diff checks pass; focusing and destructive actions remain assigned to Tickets 03–05.
