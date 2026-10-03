# Implement Launchable App search and Open Request

Type: task
Status: resolved

- [x] A non-empty Search Query appends matching Launchable Apps after Running Apps.
- [x] Desktop entries already represented by Running Apps are excluded.
- [x] Enter, the primary button, and row clicks focus or open according to result kind.
- [x] Close and Kill remain restricted to Running Apps.
- [x] Selection follows a Launchable App when it becomes a Running App.
- [x] Model checks, QML parsing, `qmllint`, and plugin validation pass.

## Answer

Implemented on `codex/launch-app-from-search` using the host's visible desktop
entry list and shared application launcher. AppDeck does not parse commands or
poll for a new window, and an Open Request does not claim that launch succeeded.
