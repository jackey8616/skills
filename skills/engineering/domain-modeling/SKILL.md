---
name: domain-modeling
description: Build and sharpen a project's domain model. Use when the user wants to pin down domain terminology or a ubiquitous language, record an architectural decision, or when another skill needs to maintain the domain model.
---

# Domain Modeling

Actively build and sharpen the project's domain model as you design. This is the *active* discipline — challenging terms, inventing edge-case scenarios, and writing the glossary and decisions down the moment they crystallise. (Merely *reading* `CONTEXT.md` for vocabulary is not this skill — that's a one-line habit any skill can do. This skill is for when you're changing the model, not just consuming it.)

## Where things go

This skill owns two of the three document layers — the **glossary** and the **decisions**. It does not own behaviour: what the system currently does lives in `openspec/specs/`, and what a change will do lives in that change's folder.

Read [DOC-LAYERS.md](./DOC-LAYERS.md) before writing anything. It is the routing rule, and it is what lets ADRs freeze and `CONTEXT.md` stay a glossary. Read `openspec/specs/` too when it exists — knowing what is already recorded there is how you tell a requirement apart from a decision.

## File structure

Most repos have a single context:

```
/
├── CONTEXT.md
├── docs/
│   └── adr/
│       ├── 0001-event-sourced-orders.md
│       └── 0002-postgres-for-write-model.md
├── openspec/                             ← behaviour, owned by OpenSpec — not this skill
└── src/
```

If a `CONTEXT-MAP.md` exists at the root, the repo has multiple contexts. The map points to where each one lives:

```
/
├── CONTEXT-MAP.md
├── docs/
│   └── adr/                          ← system-wide decisions
├── src/
│   ├── ordering/
│   │   ├── CONTEXT.md
│   │   └── docs/adr/                 ← context-specific decisions
│   └── billing/
│       ├── CONTEXT.md
│       └── docs/adr/
```

Create files lazily — only when you have something to write. If no `CONTEXT.md` exists, create one when the first term is resolved. If no `docs/adr/` exists, create it when the first ADR is needed.

## During the session

### Challenge against the glossary

When the user uses a term that conflicts with the existing language in `CONTEXT.md`, call it out immediately. "Your glossary defines 'cancellation' as X, but you seem to mean Y — which is it?"

### Sharpen fuzzy language

When the user uses vague or overloaded terms, propose a precise canonical term. "You're saying 'account' — do you mean the Customer or the User? Those are different things."

### Discuss concrete scenarios

When domain relationships are being discussed, stress-test them with specific scenarios. Invent scenarios that probe edge cases and force the user to be precise about the boundaries between concepts.

### Cross-reference with code

When the user states how something works, check whether the code agrees. If you find a contradiction, surface it: "Your code cancels entire Orders, but you just said partial cancellation is possible — which is right?"

### Update CONTEXT.md inline

When a term is resolved, update `CONTEXT.md` right there. Don't batch these up — capture them as they happen. Use the format in [CONTEXT-FORMAT.md](./CONTEXT-FORMAT.md).

`CONTEXT.md` should be totally devoid of implementation details. Do not treat `CONTEXT.md` as a spec, a scratch pad, or a repository for implementation decisions. It is a glossary and nothing else. Requirements go to the active change's delta specs — never here.

### Offer ADRs sparingly

Only offer to create an ADR when all three are true:

1. **Hard to reverse** — the cost of changing your mind later is meaningful
2. **Surprising without context** — a future reader will wonder "why did they do it this way?"
3. **The result of a real trade-off** — there were genuine alternatives and you picked one for specific reasons

If any of the three is missing, skip the ADR — silently. Don't offer one anyway, and don't mention the one you decided against. Rationale that fails the gate goes in the active change's `design.md`, where it archives with the change.

Write the ADR as numbered **decision points**, 1-3 sentences each. Most have exactly one. Use the format in [ADR-FORMAT.md](./ADR-FORMAT.md).

### Never rewrite an accepted ADR

Within a session you may **create** a new ADR, or change an existing ADR's **frontmatter**. That is the entire set of permitted writes to `docs/adr/`.

You may not edit the title, the context line, or any decision point of an accepted ADR — not to correct it, not to bring it in line with how the code works now, not to trim it to the format. When a decision is reversed, write a new ADR and mark the old one's frontmatter: `superseded` for a single point, `status` for the whole document.

If a session's work contradicts an existing ADR, say so out loud and ask whether the decision is genuinely being reversed. **Drifting behaviour is not a reversal** — that belongs in a spec update, and the ADR stays exactly as it is.
