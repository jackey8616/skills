# ADR Format

ADRs live in `docs/adr/` and use sequential numbering: `0001-slug.md`, `0002-slug.md`, etc.

Create the `docs/adr/` directory lazily — only when the first ADR is needed.

An ADR records a **decision**: what we chose, and why. It never records behaviour. See [DOC-LAYERS.md](./DOC-LAYERS.md) for what belongs where.

## Template

```md
---
status: accepted
---

# {Short title of the decision}

{One sentence of context: what made this decision necessary.}

1. {The decision, in 1-3 sentences.}
2. {A second decision point — only if the choice genuinely has separable parts.}
```

That's it. Most ADRs are a title, a line of context, and one numbered point. The value is in recording _that_ a decision was made and _why_ — not in filling out sections.

## Decision points

The numbered items are **decision points**: the addressable units of an ADR. Numbering them is what lets a later ADR supersede *part* of this one without retiring the whole document.

- **1-3 sentences each.** A hard limit, not a target. A point that won't fit is one of three things — behaviour (which belongs in a spec), several decisions bundled together (split them into separate points, or separate ADRs), or a design document (which belongs in the change's `design.md`). Write the point to the limit and put the rest where it goes.
- **Most ADRs have one point.** Add a second only when the parts could be reversed independently of each other.
- **Numbers are never reused**, even after a point is superseded. A `point: 3` reference has to mean the same thing forever.

The limit is per point, not per ADR — that is a rule about shape, not a licence to add points. What keeps ADRs rare is the gate below.

## Frontmatter

Frontmatter is the **only** part of an accepted ADR that may change. Two fields, with different jobs:

```md
---
status: superseded by ADR-0007
superseded:
  - point: 3
    by: ADR-0007
  - point: 5
    by: ADR-0009
---
```

- **`status`** — the whole document: `proposed | accepted | deprecated | superseded by ADR-NNNN`. Optional on a new ADR; one with no `status` is accepted. Add it when it becomes load-bearing rather than seeding every ADR with `status: accepted`.
- **`superseded`** — the individual decision points that no longer hold, each naming the ADR that replaced it. Any point not listed still stands.

Use `superseded` when part of an ADR is replaced and the rest survives. Use `status` when the whole thing goes. An ADR may accumulate both over its life: points fall away one at a time, and eventually the document itself is retired.

## Immutability

**An accepted ADR is frozen except for its frontmatter.** Never edit the title, the context line, or any decision point — not to correct it, not to bring it in line with how the code works now, not to reformat it into this template.

To reverse or replace a decision:

1. Write a **new** ADR with the next number, recording the new decision and, within its 1-3 sentences, why the old one no longer holds.
2. Add the old ADR's frontmatter entry — `superseded` for a point, `status` for the whole document. Change nothing else in it.

An ADR is a record of what we believed, and why, at the time we decided it. Rewriting it destroys exactly the thing it exists to preserve: a reader six months from now cannot tell whether the reasoning was sound at the time or has been quietly retrofitted. A superseded point that reads as wrong today is doing its job.

## ADRs written before this format

An older ADR is prose, with no numbered points to address. It is still frozen — restructuring it into decision points would itself be an edit, and "just adding the numbers" is how a file gets opened and then quietly improved.

So a pre-format ADR can only be superseded **whole**, through `status`. When a new decision reverses only part of one, name that part in the new ADR's own text rather than reaching back into the old file.

## Numbering

Scan `docs/adr/` for the highest existing number and increment by one. Numbers are never reused, including for ADRs that have been superseded.

## When to offer an ADR

All three of these must be true:

1. **Hard to reverse** — the cost of changing your mind later is meaningful
2. **Surprising without context** — a future reader will look at the code and wonder "why on earth did they do it this way?"
3. **The result of a real trade-off** — there were genuine alternatives and you picked one for specific reasons

If a decision is easy to reverse, skip it — you'll just reverse it. If it's not surprising, nobody will wonder why. If there was no real alternative, there's nothing to record beyond "we did the obvious thing."

When a decision fails the gate, **do not offer an ADR at all** — not as an option, not as a "we could also record this". Declining is the normal outcome; most sessions produce none. The rationale still gets written down, in the active change's `design.md`, where it archives with the change.

### What qualifies

- **Architectural shape.** "We're using a monorepo." "The write model is event-sourced, the read model is projected into Postgres."
- **Integration patterns between contexts.** "Ordering and Billing communicate via domain events, not synchronous HTTP."
- **Technology choices that carry lock-in.** Database, message bus, auth provider, deployment target. Not every library — just the ones that would take a quarter to swap out.
- **Boundary and scope decisions.** "Customer data is owned by the Customer context; other contexts reference it by ID only." The explicit no-s are as valuable as the yes-s.
- **Deliberate deviations from the obvious path.** "We're using manual SQL instead of an ORM because X." Anything where a reasonable reader would assume the opposite. These stop the next engineer from "fixing" something that was deliberate.
- **Constraints not visible in the code.** "We can't use AWS because of compliance requirements." "Response times must be under 200ms because of the partner API contract."
- **Rejected alternatives when the rejection is non-obvious.** If you considered GraphQL and picked REST for subtle reasons, record it — otherwise someone will suggest GraphQL again in six months.

### What does not

- **Requirements and behaviour.** "Orders can be partially cancelled" is a spec, not a decision. It belongs in a delta spec under the active change. An ADR that has absorbed a requirement will be read as a decision forever.
- **Anything a library swap would undo.** Picking a date formatter, a test runner, an assertion library. Reversible in an afternoon — fails gate 1.
- **Rationale that only matters for this change.** It goes in the change's `design.md` and archives with it.
- **The current state of anything.** Version numbers, what a listing reports today, what you verified last Tuesday. It rots, and an ADR is exactly the document you cannot edit to fix it. Current state is the spec layer's job.
