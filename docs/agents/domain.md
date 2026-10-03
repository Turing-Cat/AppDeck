# Domain Docs

AppDeck uses a single-context domain-documentation layout.

## Before exploring

- Read `CONTEXT.md` at the repository root.
- Read the ADRs under `docs/adr/` that affect the area being changed.
- If either location is absent, proceed silently.

## Use the glossary vocabulary

When naming a domain concept in an issue, proposal, test, or implementation, use the term defined in `CONTEXT.md`. Avoid synonyms that the glossary explicitly rejects.

If a required concept is missing, reconsider whether new terminology is necessary or record the gap for the domain-modeling workflow.

## Respect ADRs

Surface any conflict with an existing ADR explicitly instead of silently overriding it.
