# Document layers

Three layers, three lifetimes. Every piece of writing belongs to exactly one — putting it in the wrong layer is what makes documentation rot.

| Layer         | Path              | Lifetime                  | Holds                              |
| ------------- | ----------------- | ------------------------- | ---------------------------------- |
| **Behaviour** | `openspec/specs/` | Merged on every archive   | What the system does **today**     |
| **Decisions** | `docs/adr/`       | Frozen once accepted      | **Why** we chose what we chose     |
| **Language**  | `CONTEXT.md`      | Living                    | The glossary, and nothing else     |

The spec layer is what makes the other two work. Because `openspec/specs/` owns current behaviour, it absorbs the churn of ordinary work — so an ADR never has to be updated to stay accurate, and `CONTEXT.md` never has to describe how anything is built.

## Routing

Ask what kind of sentence you are writing.

| The sentence                                                        | Where it goes                                              |
| ------------------------------------------------------------------- | ---------------------------------------------------------- |
| "The system does X when Y"                                           | A delta spec in the active change; `openspec/specs/` on archive |
| "We chose A over B, and undoing it would be expensive"               | `docs/adr/` — if it clears the gate in [ADR-FORMAT.md](./ADR-FORMAT.md) |
| "We chose A over B, for reasons that stop mattering once this ships" | The change's `design.md`                                    |
| "In this project, the word *X* means…"                               | `CONTEXT.md`                                                |

Three rules follow from that table.

**Requirements never enter the other two layers.** If you catch yourself writing "the system must…" in an ADR or in `CONTEXT.md`, stop. An ADR that has absorbed a requirement will be read as a decision forever, and the next reader cannot tell which of its sentences still describe the system.

**Change-scoped rationale lives in `design.md`**, and archives with the change. Promote it to an ADR only when the trade-off outlives the change. When you do, link from `design.md` to the ADR instead of repeating it.

**`CONTEXT.md` is a glossary.** Not a spec, not a scratch pad, not a decision log.

A `wayfinder` map is **an index, not a fourth layer**: its Decisions-so-far gists what each closed ticket holds and links to it, and a resolution clearing the ADR gate is written to `docs/adr/` and linked from the map rather than left to live in the tracker.

## Drift is not staleness

When the system's behaviour moves away from what an ADR describes, **the ADR is not out of date**. `openspec/specs/` is the record of what the system does; the ADR is the record of a decision that was taken. Only a decision that has genuinely been reversed needs a new one — and reversing it means writing a new ADR, never editing the old.

This is the whole point of the split. Without a spec layer, keeping ADRs "current" means editing them, and editing them destroys the reason to keep them.

## When there is no `openspec/`

The Behaviour layer has no home. Say so, and offer to run:

```
npx @fission-ai/openspec@latest init
```

The CLI is the scoped `@fission-ai/openspec` package. The bare `openspec` name on npm is an unrelated `0.0.0` placeholder that installs no binary, so `npx openspec` fails with "could not determine executable to run". Once it is installed the binary itself is `openspec`, so post-init commands (`openspec validate`, `openspec archive`) use the bare name.

**Do not compensate by spilling behaviour into the other two layers.** A missing spec is a gap you can fill later. An ADR that has swallowed a requirement is a lie with a long half-life, because it can never be edited to remove it.
