# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Three layers, one owner each

| Layer         | Path              | Lifetime               | Holds                          |
| ------------- | ----------------- | ---------------------- | ------------------------------ |
| **Behaviour** | `openspec/specs/` | Merged on every archive | What the system does **today** |
| **Decisions** | `docs/adr/`       | Frozen once accepted   | **Why** we chose what we chose |
| **Language**  | `CONTEXT.md`      | Living                 | The glossary, and nothing else |

Two rules follow, and they bind every skill that writes here:

- **Requirements and behaviour go to the spec layer only.** Never write "the system must…" into an ADR or into `CONTEXT.md`. An ADR that has absorbed a requirement will be read as a decision forever.
- **An accepted ADR is never edited.** Only its frontmatter changes — `superseded` for one decision point, `status` for the whole document. Reversing a decision means writing a new ADR, not rewriting the old one. Behaviour drifting away from what an ADR describes is not the ADR going stale; that's a spec update.

## Before exploring, read these

- **`openspec/specs/`** — the source of truth for what the system does today. Read the capabilities relevant to the area you're touching.
- **`CONTEXT.md`** at the repo root, or
- **`CONTEXT-MAP.md`** at the repo root if it exists — it points at one `CONTEXT.md` per context. Read each one relevant to the topic.
- **`docs/adr/`** — read ADRs that touch the area you're about to work in. In multi-context repos, also check `src/<context>/docs/adr/` for context-scoped decisions.

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates them lazily when terms or decisions actually get resolved.

## File structure

Single-context repo (most repos):

```
/
├── CONTEXT.md
├── docs/adr/
│   ├── 0001-event-sourced-orders.md
│   └── 0002-postgres-for-write-model.md
├── openspec/
│   ├── specs/                         ← current behaviour
│   └── changes/                       ← what's in flight
└── src/
```

Multi-context repo (presence of `CONTEXT-MAP.md` at the root):

```
/
├── CONTEXT-MAP.md
├── docs/adr/                          ← system-wide decisions
└── src/
    ├── ordering/
    │   ├── CONTEXT.md
    │   └── docs/adr/                  ← context-specific decisions
    └── billing/
        ├── CONTEXT.md
        └── docs/adr/
```

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal — either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (event-sourced orders) — but worth reopening because…_
