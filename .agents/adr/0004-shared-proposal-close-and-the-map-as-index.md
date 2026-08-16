---
status: accepted
---

# The wayfinder map is an index, and the proposal close is a shared skill

`wayfinder` was the only flow with no route into the document layers, and the close that writes a proposal lived inside `grill-with-docs`, which no other skill in this repo is allowed to reach.

1. A `wayfinder` map is an **index** over its decision tickets, not a fourth document layer. A resolution clearing the ADR gate is written to `docs/adr/` and linked from the map line, and terms land in `CONTEXT.md` as each ticket resolves rather than batched to the close — batching would force the closing session to re-read every closed ticket, which is the context blow-up the map exists to prevent.
2. Scaffolding the change and writing `proposal.md` and `design.md` moves out of `grill-with-docs` into a new **model-invoked** `writing-proposals`. A user-invoked skill can never reach another user-invoked one, and both `grill-with-docs` and `wayfinder` are user-invoked, so a shared close has to be model-invoked; the alternative was a second hand-synced copy of the closing steps inside `wayfinder`.
3. `writing-proposals` delegates the scaffold to the repo's generated `openspec-propose` workflow instead of writing the folder itself, because a change's artifact set, their order, templates and output paths are schema-driven and only resolvable at runtime — a hard-coded `proposal.md`/`design.md`/`tasks.md` is correct only for the default schema.
