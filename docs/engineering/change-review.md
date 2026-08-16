## What it does

`change-review` is the gate between a finished OpenSpec change and the archive. It reconciles the change's checklist against your tracker, reviews the whole change against its own delta specs on two axes, and — only if both come back clean — archives it, merging the deltas into `openspec/specs/`.

It is the only step that updates current behaviour. Everything before it writes proposals, deltas and code; this is where the record of what the system *does* actually moves. That is also why it will not resolve a finding by editing a delta [spec](https://www.aihero.dev/ai-coding-dictionary/spec) to match what got built — a spec edited after the fact stops being an agreement and becomes a transcript, and the layer that was supposed to be trustworthy quietly isn't.

## When to reach for it

You invoke this by typing `/change-review` — the [agent](https://www.aihero.dev/ai-coding-dictionary/agent) won't reach for it on its own.

| Where you are | What to run |
| --- | --- |
| Tickets still open on the change | Finish them — this skill stops and names the open ones |
| Every ticket merged, change not archived | `/change-review` |
| Reviewing one ticket's diff before committing | [code-review](https://aihero.dev/skills-code-review) instead |
| Nothing merged yet, you want progress | Read `tasks.md` — this is a gate, not a status report |

## Prerequisites

An initialized `openspec/` with an active change that has delta specs and a `tasks.md`, produced by [to-spec](https://aihero.dev/skills-to-spec) and [to-tickets](https://aihero.dev/skills-to-tickets). It also reads your tracker to check each ticket's real state, so [setup-matt-pocock-skills](https://aihero.dev/skills-setup-matt-pocock-skills) must have configured one.

## The two axes

A [ticket](https://www.aihero.dev/ai-coding-dictionary/ticket) can pass its own review and the change still be wrong. These are the two ways that happens, and they run as parallel [subagents](https://www.aihero.dev/ai-coding-dictionary/subagent) so neither colours the other:

| Axis | The question | What it catches |
| --- | --- | --- |
| **Coverage** | Is every proposed thing actually there? | A requirement nobody built; a scenario that works but has no test holding it in place |
| **Fidelity** | Is anything there that *shouldn't* be? | Scope decided during implementation; a `design.md` decision the code quietly abandoned |

The most common Coverage finding is a scenario with no test. The behaviour works today, nothing pins it, and the next change breaks it without anything going red.

## Why it isn't part of `implement`

[implement](https://aihero.dev/skills-implement) finishes at a commit, so its [session](https://www.aihero.dev/ai-coding-dictionary/session) is over before the work merges. At the moment the last pull request lands — the moment the change becomes archivable — nothing is running.

That gap is the whole reason this is a command you type. Folding the archive into the last ticket would mean archiving before the ticket has landed, which writes behaviour into current state that review or CI might still reject.

## Common questions

**Can't `/implement` just archive when it finishes the last ticket?**
Only by archiving too early. Its session ends at the commit, before the pull request exists, so the earliest it could act is well before the work has landed — and "the last ticket" isn't knowable in advance when tickets have blocking edges and finish in parallel. The trade-off is deliberate: a later archive costs you a stale spec layer for a day, an early one costs you a spec layer nobody can trust.

**What if I just run `openspec archive` myself?**
It works, and it skips both axes. You get the current-state update without the check that the change delivered what it proposed, so a requirement nobody built simply disappears from the record. Reach for it directly only when the change was a single ticket you reviewed yourself.

**A finding says a requirement wasn't built, but we decided during implementation not to build it. Do I edit the spec?**
No — that's the one move this gate exists to catch. Take it back through the propose stage and amend the change, so the decision to drop it is recorded where decisions live. Editing the delta instead leaves no trace that anything changed, and the next reader sees a spec that was never really agreed.

**Why does it re-check my ticks instead of trusting `tasks.md`?**
Because a box is ticked when its issue closes, and no session is running then. Ticks in `tasks.md` are as likely to be stale as accurate, so it reconciles them against the tracker using the issue references [to-tickets](https://aihero.dev/skills-to-tickets) wrote back.

## It's working if

- It refuses to run while any ticket is open, and names the ones blocking it.
- Coverage findings are mostly missing *tests*, not missing code — that's the gap per-ticket review is worst at seeing.
- Fidelity finds at least one thing you'd forgotten was decided mid-build.
- After a clean run, `openspec/specs/` has actually changed, and it says so.
- You never end a run by editing a delta spec.

## Where it fits

`change-review` is the last step in the main build chain, and the one that closes the loop:

```txt
grill-with-docs → to-spec → to-tickets → implement → code-review → change-review
```

Its neighbour is [code-review](https://aihero.dev/skills-code-review), which asks the same kind of question one scale down — a diff against one ticket, where this is a whole change against its delta specs. Upstream, [to-spec](https://aihero.dev/skills-to-spec) wrote the deltas this measures against. When you're unsure which skill or flow fits, [ask-matt](https://aihero.dev/skills-ask-matt) routes you.
