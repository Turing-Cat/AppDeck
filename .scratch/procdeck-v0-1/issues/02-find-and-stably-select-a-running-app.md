# 02: Find and stably select a Running App

**What to build:** Let a keyboard-first user quickly find a Running App and keep a predictable Selected App while desktop state and the Search Query change.

**Blocked by:** 01: Open ProcDeck and view Running Apps.

**Status:** ready-for-agent

- [ ] Running Apps appear in Activity Order with the Active App first and the Previous App second.
- [ ] Opening ProcDeck initially selects the Previous App when it exists, allowing an immediate Enter action to switch back.
- [ ] Focus changes update Activity Order from live desktop events without polling.
- [ ] A Search Query matches application name, reported identity, and any grouped App Window title case-insensitively.
- [ ] Space-separated search terms use AND semantics: every term must match at least one searchable field in the same Running App.
- [ ] Typing filters the list, and Escape clears a non-empty Search Query before it can dismiss the overlay.
- [ ] Up, Down, Page Up, Page Down, Home, and End move the Selected App according to the interaction contract; mouse selection is also supported.
- [ ] Live updates preserve the Selected App while it still exists, and a newly appearing Running App never steals selection.
- [ ] When the Selected App disappears, the nearest remaining visible row becomes selected; removing the final result produces an empty state without dismissing ProcDeck.
- [ ] An empty desktop and a Search Query with no matches have distinct visible states.
- [ ] The dependency-free model self-check covers filtering, Activity Order, initial selection, and selection reconciliation through observable results.
