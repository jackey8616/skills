---
"mattpocock-skills": minor
---

Connect `wayfinder` to the spec layer, and share the proposal close between the flows that need it.

`wayfinder` was the one flow the spec layer never reached. It produces the most decisions of anything here — greenfield builds, multi-session features — and had no route into `CONTEXT.md`, `docs/adr/` or a change: resolutions stopped at a comment on a closed issue. Worse, `ask-matt` advertised a handoff to `to-spec` that could not work, because `to-spec` starts from a proposal and a map never wrote one, and its fallback of rebuilding from the conversation is exactly what a map cannot offer.

The cause was structural, not an omission. The close that scaffolds a change and writes its proposal lived inside `grill-with-docs`, and a user-invoked skill can never reach another user-invoked one — so `wayfinder` had no way to borrow it.

- **New skill: `writing-proposals`** — model-invoked, so both `grill-with-docs` and `wayfinder` can reach it. It opens the change, writes the Proposal and the trade-offs half of `design.md`, and never interviews: it writes down what a caller already settled, from any source. Where the repo has no `openspec/` it says so and stops, which is now the one place that rule lives instead of two.
- It **wraps** the repo's generated `openspec-propose` workflow rather than scaffolding itself. Which artifacts a change has, in what order, from which template and to which path is schema-driven and resolved at runtime, so a hard-coded folder shape is right only for the default schema.
- **`wayfinder` gains a third mode, `Close the map`.** The map previously had no terminal step at all — "Work through the map" simply looped. Closing checks the way is genuinely clear (open tickets gone, **Not yet specified** empty), collects what the closed tickets agreed, rejected and ruled out of scope, pushes it through `writing-proposals`, and closes the map. The map's **Out of scope** becomes the Proposal's out-of-scope section — thinking that was recorded nowhere else and used to be dropped on the floor.
- **`wayfinder` resolutions now reach the document layers**, ticket by ticket rather than batched. `CONTEXT.md` is open to all four ticket types; the ADR gate applies to `grilling` and `prototype` only, since `research` produces facts and `task` produces state, and neither is a decision.
- The map is stated to be an **index, not a fourth document layer**, in `DOC-LAYERS.md` and in `CONTEXT.md`, which gains **Map** and **Destination** as terms. `wayfinder` stops describing a destination as "a spec, decision, or change" — all three had become load-bearing terms meaning something else.
- Each tracker doc (`github`, `gitlab`, `local`) gains a **Close the map** operation, so the local-markdown tracker isn't left with an undefined action.
