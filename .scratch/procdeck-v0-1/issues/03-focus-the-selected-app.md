# 03: Focus the Selected App

**What to build:** Let a user activate the most recently used App Window belonging to the Selected App and return immediately to that application.

**Blocked by:** 02: Find and stably select a Running App.

**Status:** resolved

- [x] Enter, clicking a Running App row, and the visible Focus action all activate the Selected App.
- [x] Focus targets the most recently active App Window within the Selected App.
- [x] A successful focus action dismisses ProcDeck.
- [x] Focus uses the shell's native App Window activation capability and does not spawn a shell command.
- [x] An unavailable or failed target leaves ProcDeck usable and displays a short inline footer error.
- [x] Focus never activates an App Window belonging to a different Running App.
- [x] Observable model or boundary checks verify that the correct App Window is selected when a Running App owns multiple windows.

## Answer

Enter, Running App row clicks, and the visible Focus action now share one native activation boundary. ProcDeck refreshes focus history from live Hyprland events, chooses only an unambiguous most-recent App Window within the Selected App, and dismisses after that native target reports itself activated. Missing, ambiguous, thrown, or unacknowledged targets keep the overlay usable with an inline footer error, while late activation acknowledgements remain accepted. Ten dependency-free model checks and all repository validation, QML parsing/linting, and diff checks pass.
