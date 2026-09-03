# ProcDeck

ProcDeck provides a shared language for managing running graphical applications
across an Omarchy desktop.

## Language

**ProcDeck**:
A keyboard-first, desktop-wide running-application switcher whose secondary
capabilities allow applications to be closed or forcibly ended.
_Avoid_: Process manager, task manager

**Running App**:
One or more app windows that the desktop reports as sharing the same
application identity.
_Avoid_: App group, process, task

**App Window**:
A normal graphical application window managed by the desktop and belonging to
one running app.
_Avoid_: Process, client

**Active App**:
The running app that owns the currently focused app window.
_Avoid_: Focused row

**Selected App**:
The running app currently targeted by ProcDeck's focus and termination actions.
It may differ from the active app.
_Avoid_: Active app

**Previous App**:
The most recently active running app other than the active app. It is the
initial selection when ProcDeck opens.
_Avoid_: Last app

**Unidentified App**:
A running app containing one app window for which the desktop reports no
application identity. Unidentified app windows are never grouped together.
_Avoid_: Unknown process

**Dialog Window**:
An app window with an explicit parent window. It belongs to the same running
app as its parent.
_Avoid_: Separate app

**Graceful Close**:
A request for every app window in the selected app to close through its normal
application-controlled shutdown flow.
_Avoid_: Kill, terminate

**Force Kill**:
An explicitly confirmed request for the desktop to immediately end the window
owners belonging to the selected app, without privilege elevation.
_Avoid_: Close, process-tree kill

**Search Query**:
One or more case-insensitive terms that must each match the running app's name,
reported identity, or one of its app-window titles.
_Avoid_: Fuzzy query

**Activity Order**:
The ordering of running apps from most to least recently active, with the active
app first and the previous app second.
_Avoid_: Alphabetical order, workspace order

**Close Request**:
The acknowledged sending of a graceful-close request. It does not claim that
the receiving app has exited or accepted the request.
_Avoid_: Closed app, successful exit
