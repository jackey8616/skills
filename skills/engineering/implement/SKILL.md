---
name: implement
description: "Implement a piece of work based on a spec or set of tickets."
disable-model-invocation: true
---

Implement the work described by the user in the spec or tickets.

## Read the change first

When the ticket belongs to an OpenSpec change, read that change's `proposal.md`, `design.md`, and the delta specs before writing anything. Read `openspec/specs/` too — it says what the system does today, which is what your change is measured against.

Build **only the requirements this ticket covers**. If you find scope the delta specs don't describe, stop and say so rather than absorbing it: scope is decided at propose time, not during implementation. The whole change is `/change-review`'s job, not yours — you are responsible for one ticket.

## Build it

Use /tdd where possible, at pre-agreed seams.

Run typechecking regularly, single test files regularly, and the full test suite once at the end.

Once done, use /code-review to review the work.

Commit your work to the current branch.

## Closing out

Hand the merge off — don't close the ticket yourself. A ticket's box in `tasks.md` is ticked when its issue closes, which happens after the work merges, and this session ends before that. `/change-review` reconciles `tasks.md` against the tracker when the change is finished.
