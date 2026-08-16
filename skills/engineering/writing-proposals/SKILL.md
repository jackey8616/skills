---
name: writing-proposals
description: Open an OpenSpec change and write its proposal — the problem, the agreed solution, and what was ruled out. Use when a design has been settled and needs to become a change on disk, when the user asks to open or scaffold a change, or when another skill closes by writing a proposal.
---

# Writing Proposals

Turn something **already agreed** into a Change on disk: its folder, its `proposal.md`, and the trade-offs half of its `design.md`.

**Do not interview.** Whoever called you has done that — a `/grilling` session, a `wayfinder` map, a conversation that reached its own conclusion. You add nothing to the design; you write down what was settled. If a question surfaces that would change the shape of the work, hand it back rather than deciding it yourself.

You are also **source-agnostic**. The caller brings the agreed material; how they gathered it — one conversation, or fifty closed tickets — is theirs to know, not yours.

## Precondition

`openspec/` must exist in the repo. If it doesn't, **say so and stop**, offering:

```
npx @fission-ai/openspec@latest init
```

The CLI is the scoped `@fission-ai/openspec` package. The bare `openspec` name on npm is an unrelated `0.0.0` placeholder that installs no binary, so `npx openspec` fails with "could not determine executable to run". Once it is installed the binary itself is `openspec`.

Stopping is the whole behaviour. Don't invent another home for the proposal, and don't push it into `CONTEXT.md` or an ADR to compensate — what was agreed stays in the conversation, which is where it lived before this skill existed. A repo that silently keeps working without the spec layer never grows one.

## The toolchain owns the folder

`openspec init` generates a proposal workflow into the repo — a skill of its own, usually reachable as `openspec-propose`. **Prefer it over writing the folder yourself.** It resolves the change's workflow schema at runtime, then walks the artifact dependency graph, asking the CLI for each artifact's template, rules and output path as it goes.

That runtime resolution is exactly why this skill doesn't scaffold. Which artifacts a change has, in what order, from which template, written to which path, is **schema-driven** — a hard-coded `proposal.md` + `design.md` + `tasks.md` is right for the default schema and wrong for every other one, and wrong again wherever the planning home isn't repo-local.

Where the repo has no generated workflow, follow the agent instructions `openspec init` produced (`openspec/AGENTS.md` or equivalent) and let `openspec new change "<name>"` do the scaffolding. Either way the format is theirs, not this skill's.

## What you own: the content

The generated workflow knows the *shape* of a proposal. It does not know what this project puts in one.

### `proposal.md`

Three things, and nothing else:

- **The problem** — what is wrong now, stated so a reader outside the conversation can feel it.
- **The solution, in the user's own words.** Their phrasing survived the interview for a reason; a tidier paraphrase loses the thing that made them agree to it.
- **What is explicitly out of scope** — considered, and ruled out. This is the half that gets dropped, and it is the expensive half: it records thinking that happened, so nobody re-opens it in a month.

**No requirements, no scenarios.** "The system must…" and "when X, then Y" belong to the delta specs, and `/to-spec` writes those. A proposal that has absorbed its own requirements gives `/to-spec` two sources that can disagree.

### `design.md`

The **trade-offs**: what was rejected, and why it lost. Write the rejections that a reader would otherwise re-propose; skip the ones nobody would.

**Leave the file open.** `/to-spec` appends the technical half later — the seams, the testing approach — so don't close it off with a conclusion or a summary.

## Rationale that outlives the change

Most rationale belongs in `design.md`, and archives with the change. A decision that is **hard to reverse**, **surprising without context**, *and* **the result of a real trade-off** belongs in an ADR instead — that is `/domain-modeling`'s gate and its file, not yours. Where one clears it, link `design.md` to the ADR rather than repeating it.

Writing an ADR is not part of closing a change, and most changes produce none.

## Where the output goes

`/to-spec` picks the work up from the Proposal — it does not interview again. Because the Proposal is a file rather than a conversation, finishing here is a clean place to `/clear`.
