# Issue tracker: Local Markdown

Issues and specs for this repo live as Markdown files in `.scratch/`.

## Conventions

- One feature per directory: `.scratch/<feature-slug>/`
- The spec is `.scratch/<feature-slug>/spec.md`
- Implementation issues are one file per ticket at `.scratch/<feature-slug>/issues/<NN>-<slug>.md`, numbered from `01`
- Triage state is recorded as a `Status:` line near the top of each issue file
- Comments and conversation history append under a `## Comments` heading

## Publishing

When a skill says to publish to the issue tracker, create the appropriate file under `.scratch/<feature-slug>/`, creating the directory if needed.

## Fetching

When a skill says to fetch a ticket, read the referenced local Markdown file. The user will normally provide its path or issue number.

## Wayfinding operations

- Map: `.scratch/<effort>/map.md`
- Child ticket: `.scratch/<effort>/issues/NN-<slug>.md`
- A `Type:` line records `research`, `prototype`, `grilling`, or `task`
- A `Status:` line records `claimed` or `resolved`
- A `Blocked by: NN, NN` line records dependencies
- The frontier is the first open, unblocked, unclaimed ticket by number
- Claim a ticket by setting `Status: claimed` before starting work
- Resolve a ticket by appending its answer under `## Answer`, setting `Status: resolved`, and adding a context pointer to the map
