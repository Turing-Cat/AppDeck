# Selected App window-list layout

Status: resolved

## Decision

The user selected variant B of the layout prototype: an application list on the
left and Selected App details with a window list and actions on the right.
Prototype source: /home/zjh/.codex/visualizations/2026/10/03/01a100dd-4f09-7091-9ec7-1d8c9082cac6/appdeck-layout-prototype.html (variant B).

## Implementation

- The application list takes approximately 37% of body width.
- Selected App details occupy the right column; no duplicated bottom card.
- App Window rows show live titles and workspaces, with a most-recent highlight.
- Window rows are informational. Existing app-level keyboard and mouse actions
  remain unchanged. Close and Kill still target all Selected App windows.
- Window lists scroll and titles wrap to two lines. Launchable Apps show their
  installed state and Start Running. Empty results show No selection.
- Below 720 theme-scaled units, the columns stack vertically.
- Omarchy styling and the existing native search input remain in use.

## Validation

- Existing 26 model tests and 14 real Qt input integration steps pass.
- Qt 6 QML parser, plugin validation, and git diff whitespace checks pass.
- Live desktop layout inspected after reloading the installed plugin.
