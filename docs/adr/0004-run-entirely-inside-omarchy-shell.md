# Run entirely inside the Omarchy shell

AppDeck runs as a pure Quickshell QML and JavaScript plugin that consumes the
desktop's native live window objects. It adds no daemon, helper backend,
process-list polling, independent theme, or settings subsystem because the
host shell already provides the required lifecycle, window actions, styling,
and configuration boundary.
