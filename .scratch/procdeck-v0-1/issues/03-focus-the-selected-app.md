# 03: Focus the Selected App

**What to build:** Let a user activate the most recently used App Window belonging to the Selected App and return immediately to that application.

**Blocked by:** 02: Find and stably select a Running App.

**Status:** ready-for-agent

- [ ] Enter, clicking a Running App row, and the visible Focus action all activate the Selected App.
- [ ] Focus targets the most recently active App Window within the Selected App.
- [ ] A successful focus action dismisses ProcDeck.
- [ ] Focus uses the shell's native App Window activation capability and does not spawn a shell command.
- [ ] An unavailable or failed target leaves ProcDeck usable and displays a short inline footer error.
- [ ] Focus never activates an App Window belonging to a different Running App.
- [ ] Observable model or boundary checks verify that the correct App Window is selected when a Running App owns multiple windows.
