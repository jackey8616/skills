## What it does

`writing-proposals` turns something already agreed into an OpenSpec change on disk: the change folder, its `proposal.md`, and the trade-offs half of its `design.md`.

It never interviews you. Whatever settled the design — a grilling [session](https://www.aihero.dev/ai-coding-dictionary/session), a wayfinder map, a conversation that reached its own conclusion — did that work already, and this skill only writes it down; a question big enough to move the shape of the work gets handed back rather than answered. That refusal is what makes it source-agnostic, and source-agnostic is what lets two different flows finish the same way instead of each carrying its own copy of the close.

## When to reach for it

Type `/writing-proposals`, or the [agent](https://www.aihero.dev/ai-coding-dictionary/agent) reaches for it automatically when a task fits — most often you never type it at all, because the skill that ran the design calls it on the way out.

| Where you are | What to run |
| --- | --- |
| A design just settled, and you're in a repo | `/writing-proposals` — or let the closing skill call it |
| The design isn't settled yet | [grill-with-docs](https://aihero.dev/skills-grill-with-docs) first; this skill will not interview you |
| A proposal exists, you need the delta specs | [to-spec](https://aihero.dev/skills-to-spec) |
| A wayfinder map still has open tickets | Keep resolving them — [wayfinder](https://aihero.dev/skills-wayfinder) closes *through* this skill |

## Prerequisites

An initialized `openspec/`. Without one the skill says so, offers `npx @fission-ai/openspec@latest init`, and stops.

Stopping is the behaviour, not a failure to handle the case. A repo that silently keeps working without the spec layer never grows one, and a proposal shoved into `CONTEXT.md` or an ADR to compensate is worse than no proposal — those layers cannot be edited back out later.

## The toolchain owns the folder

`openspec init` generates a proposal workflow into your repo, usually reachable as `openspec-propose`. This skill prefers it over writing the folder itself, and that preference is the load-bearing design choice.

The reason is that an OpenSpec change's shape is resolved at runtime. The workflow reads the change's schema, walks the artifact dependency graph, and asks the CLI for each artifact's template, rules and output path as it goes. Hard-coding `proposal.md` + `design.md` + `tasks.md` would be right for the default schema and wrong for every other one — and wrong again anywhere the planning home isn't repo-local.

So the split is: **the toolchain owns the folder, this skill owns the content.** The generated workflow knows the shape of a proposal; it does not know what your project puts in one.

## What belongs in a proposal

| Goes in `proposal.md` | Why |
| --- | --- |
| The problem | Stated so a reader outside the conversation can feel it |
| The solution, in your own words | Your phrasing survived the interview for a reason; a tidier paraphrase loses it |
| What is explicitly out of scope | Considered and ruled out — the half that gets dropped, and the expensive one |

Requirements and scenarios are not among them. "The system must…" and "when X, then Y" are the delta [specs](https://www.aihero.dev/ai-coding-dictionary/spec), and [to-spec](https://aihero.dev/skills-to-spec) writes those. A proposal that has absorbed its own requirements hands `to-spec` two sources that can disagree.

`design.md` gets the trade-offs — what was rejected and why it lost — and is left open, because `to-spec` appends the technical half later.

## Common questions

**Why isn't this just part of `grill-with-docs`?**
It was, and then `wayfinder` needed the identical close. Both are user-invoked skills, and a user-invoked skill can never reach another one — so sharing the close required extracting it into a model-invoked skill that either can call. The alternative was maintaining two copies of the same closing steps in two files, which is how they drift.

**How is this different from OpenSpec's own `openspec-propose`?**
That workflow owns the mechanics: it scaffolds the change and resolves which artifacts exist from the schema. This one owns the editorial rules — what goes in a proposal, what is a requirement in disguise, and the refusal to interview. It calls `openspec-propose` rather than competing with it.

**What if the design isn't fully settled?**
Then this is the wrong skill and it will tell you. It has no rounds and no frontier; it writes down conclusions. Go back through [grill-with-docs](https://aihero.dev/skills-grill-with-docs) and come back when the questions have run out.

## It's working if

- It asks you nothing about the design — at most, how to word something you already decided.
- `proposal.md` contains no "the system must…" sentences.
- The out-of-scope section isn't empty. If it is, either the design never ruled anything out, or the ruling-out got lost on the way here.
- `design.md` stops mid-thought, with no summary or conclusion — `to-spec` is going to append to it.
- In a repo without `openspec/`, it stops, tells you, and your agreed design is still sitting in the conversation.

## Where it fits

`writing-proposals` is a chain step, and the join between the design half of the flow and the build half:

```txt
grill-with-docs → writing-proposals → to-spec → to-tickets → implement → code-review → change-review
```

It is also how [wayfinder](https://aihero.dev/skills-wayfinder) finishes: when the map's last ticket closes, a final session collects what the closed tickets agreed, rejected and ruled out, and pushes it through this skill onto the same chain. Downstream, [to-spec](https://aihero.dev/skills-to-spec) picks the work up from the proposal without interviewing anyone again. When you're unsure which skill or flow fits, [ask-matt](https://aihero.dev/skills-ask-matt) routes you.
