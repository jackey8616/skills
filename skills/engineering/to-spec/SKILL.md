---
name: to-spec
description: Turn the current conversation into an OpenSpec change proposal — no interview, just synthesis of what you've already discussed.
disable-model-invocation: true
---

This skill turns what has already been agreed into the **delta specs** of an OpenSpec change. Do NOT interview the user — just synthesize what you already know.

The issue tracker and triage label vocabulary should have been provided to you — run `/setup-matt-pocock-skills` if not.

## Precondition

This skill writes OpenSpec artifacts, so `openspec/` must be initialized in the repo. If it isn't, **stop** and tell the user to run:

```
npx @fission-ai/openspec@latest init
```

The CLI is the scoped `@fission-ai/openspec` package — the bare `openspec` name on npm is an unrelated `0.0.0` placeholder that installs no binary. Do not fall back to publishing the spec somewhere else: a repo that keeps working without the spec layer never grows one.

Before writing, read the agent instructions `openspec init` generated (`openspec/AGENTS.md` or equivalent). **They own the exact artifact format, not this skill** — follow them over anything written here about file shape. Read `openspec/specs/` too: it is the source of truth for what the system does *today*, and the delta you're about to write is measured against it.

## Start from the Proposal

`/grill-with-docs` closes by scaffolding the change and writing `proposal.md` — the problem, the solution in the user's words, and what's out of scope. Read it. It is the handoff, which is why this skill doesn't need the grilling's context window.

If there's no Proposal because the work didn't come through a grilling, write one from the conversation before going further. Everything below assumes it exists.

## Process

1. Explore the repo to understand the current state of the codebase, if you haven't already. Use the project's domain glossary vocabulary throughout, and respect any ADRs in the area you're touching.

2. Sketch out the seams at which you're going to test the feature. Existing seams should be preferred to new ones. Use the highest seam possible. If new seams are needed, propose them at the highest point you can. The fewer seams across the codebase, the better - the ideal number is one.

Check with the user that these seams match their expectations.

3. Write the change, into the folder the grilling scaffolded:

<what-goes-where>

| What you have                                                                    | Where it goes                                                        |
| -------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| Problem statement, the solution in the user's terms, what's explicitly out of scope | `proposal.md` — already written by the grilling; amend only if it's wrong |
| Every behaviour the change adds, modifies or removes — as delta requirements with scenarios | `specs/<capability>/spec.md`                                          |
| The seams, the testing approach, and any technical decision the grilling didn't reach | `design.md` — **append**; the grilling already wrote the trade-offs and rejected alternatives |
| The implementation checklist                                                      | `tasks.md` — leave it empty. `/to-tickets` fills it once this proposal has merged |

</what-goes-where>

Be extensive in the delta specs. Every user story you would have written belongs there as a requirement with concrete scenarios — that list is the spec, and it should cover all aspects of the feature.

Do NOT include specific file paths or code snippets. They may end up being outdated very quickly.

Exception: if a prototype produced a snippet that encodes a decision more precisely than prose can (state machine, reducer, schema, type shape), inline it in `design.md` within the relevant decision and note briefly that it came from a prototype. Trim to the decision-rich parts — not a working demo, just the important bits.

4. **Publish one issue to the tracker, pointing at the change.** Title it after the change, link to the change folder, and summarise the problem in a sentence or two. Apply the `ready-for-agent` triage label.

The issue is a **pointer, not a copy**. Never restate the requirements in it — the delta specs are the single source of truth, and a second copy on the tracker will drift from them within a week. What the tracker gives you is visibility and a grabbable unit of work; what OpenSpec gives you is the content.

5. Validate the change against the OpenSpec toolchain (`openspec validate <change-id> --strict`, or whatever the generated instructions specify) before handing back.

## Rationale that outlives the change

`design.md` archives with the change. That's the right home for almost all of it.

Promote a decision to an ADR under `docs/adr/` only when the trade-off is **hard to reverse**, **surprising without context**, and **the result of a real trade-off** — the gate in `/domain-modeling`'s [ADR-FORMAT.md](../domain-modeling/ADR-FORMAT.md). When you promote one, link to it from `design.md` instead of repeating the prose. Most changes promote nothing.

Never write a requirement into an ADR. Behaviour belongs to the spec layer, and only there.

## After approval

Once the user approves the proposal, its scope is fixed. If new scope surfaces during implementation, it goes back through the propose stage — amend the change, or open a new one — and gets approved again. Don't absorb it silently into an approved change.

The proposal is reviewed and merged on its own, before any implementation work is sliced. `/to-tickets` runs **after** that merge: it breaks the change into tracer-bullet tickets, writes them into `tasks.md`, and publishes one issue each. Slicing an unmerged proposal produces tickets for work that may still move.
