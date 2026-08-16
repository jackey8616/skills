---
name: change-review
description: Review a finished OpenSpec change against its own delta specs, then archive it — every requirement built and tested, nothing shipped that wasn't proposed.
disable-model-invocation: true
---

# Change Review

The gate before a change is archived, and the only thing that updates `openspec/specs/`. It asks the one question no per-ticket review can answer: **did the change, as a whole, deliver what it proposed — and only what it proposed?**

`/code-review` reviews a diff against one ticket. This reviews a **change** against its delta specs. Tickets can each pass on their own and still add up to a change with a requirement nobody built, a scenario nobody tested, or three features nobody proposed.

## Why this is a separate step

`/implement` finishes at a commit, so its session ends before anything merges. Nothing is running at the moment the last pull request lands — which is exactly when the change becomes archivable. That gap is what this skill fills, and it is why archiving is a command you run rather than something a previous step could have done for you.

## 1. Reconcile `tasks.md`

Read `openspec/changes/<change-id>/tasks.md` and check each ticket against the tracker, using the issue references `/to-tickets` wrote back. Tick the boxes whose issues have closed.

Do not trust the ticks that are already there — a box is ticked when its issue closes, and the session that wrote the code was over before that happened. Reconciling against the tracker is what makes the checklist true.

If any ticket is still open, **say which and stop.** This is a gate, not a progress report.

## 2. Assemble the record

Read the change in full: `proposal.md`, every delta spec under `specs/`, `design.md`, and the reconciled `tasks.md`. Then get the whole diff the change produced — from the base the proposal merged at, through the merge of every ticket, to `HEAD`.

Read `openspec/specs/` too. The delta describes what should now be different; the current specs describe what was true before.

## 3. Review on two axes

Run these as **parallel sub-agents**, one per axis, so neither pollutes the other. Each gets the record from step 2 and reports findings only — no fixes.

<coverage-axis>

**Coverage** — is every proposed thing actually there?

Walk the delta specs requirement by requirement, and within each, scenario by scenario. For each one, find:

- the code that implements it, and
- a test that exercises it — one that would fail if the behaviour were removed

Report every requirement or scenario missing either. A scenario with no test is the most common finding here: the behaviour works, nothing holds it in place, and the next change silently breaks it.

</coverage-axis>

<fidelity-axis>

**Fidelity** — is anything there that shouldn't be?

Walk the diff and trace each meaningful behaviour change back to a requirement in the delta specs. Report:

- **Scope drift** — behaviour shipped that no requirement asked for. It was decided during implementation, which is exactly where scope isn't supposed to be decided.
- **Abandoned decisions** — `design.md` says one thing and the code does another, with no record of the change of mind.
- **Silent requirement changes** — a requirement implemented differently from how its scenarios describe it.

</fidelity-axis>

## 4. Verdict

Present both reports under `## Coverage` and `## Fidelity`. Then one of two outcomes:

**Findings on either axis → send it back.** Say what has to happen: build the missing requirement, add the missing test, or take the unproposed behaviour back through the propose stage. **Never resolve a finding by editing a delta spec to match what got built** — that turns the record of what was agreed into a transcript of what happened, and it is the failure this gate exists to catch. If the change genuinely should cover more, amend the proposal and get it approved again.

**Clean → archive.** Run the repo's archive command (`openspec archive <change-id>`, or whatever the generated agent instructions specify). This merges the deltas into `openspec/specs/`, which is the only moment current behaviour is updated. Confirm afterwards that the specs moved, and say so.
