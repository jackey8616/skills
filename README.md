# Skills

Agent skills for real engineering work: sharpening an idea by interview, turning it into specs and tickets, building it test-first, and reviewing what came out.

They are plain Markdown, not a framework. Each one is small enough to read in a sitting and edit to taste, and they compose with each other rather than owning your process. 27 skills, for Claude Code, Codex, and other Agent Skills-compatible harnesses.

## Install

Clone the repo, then link every skill into the local harness directories:

```bash
git clone git@github.com:jackey8616/skills.git
cd skills
scripts/link-skills.sh
```

That symlinks each skill into `~/.claude/skills` and `~/.agents/skills`. Because they are symlinks back into the clone, `git pull` updates every installed skill at once, and an edit here takes effect on the next invocation. Re-run the script after adding, removing, or renaming a skill.

Then, once in each repo you want to use them in:

```
/setup-skills
```

It asks which issue tracker the repo uses, which labels `/triage` should apply, and where docs belong — then initialises the spec layer (`openspec/`) that the engineering flow writes into.

### Claude Code cloud containers

A cloud container is ephemeral: the clone is fresh and `~/.claude/skills` is empty every session. A `SessionStart` hook is committed at [.claude/settings.json](.claude/settings.json), so a session opened on this repo links every skill before its first turn — nothing to type.

For a session opened on a *different* repo, clone this one and link from that repo's own hook, or from the environment's setup script:

```bash
git clone --depth 1 https://github.com/jackey8616/skills.git ~/skills 2>/dev/null \
  || git -C ~/skills pull --ff-only
bash ~/skills/scripts/link-skills.sh
```

The link is live in the session that ran it — no restart. Model-invoked skills show up in the listing immediately; user-invoked ones are installed but stay out of it, so type the slash command anyway ([why](docs/engineering/ask.md)).

## How a skill is reached

Skills split on one axis: who can invoke them.

**User-invoked** skills run only when you type them, like `/grill-me`. They orchestrate — driving other skills, and asking you the questions only you can answer.

**Model-invoked** skills can be typed *or* reached for by the agent when a task fits. They hold the reusable discipline: the interview primitive, the review, the design vocabulary.

A user-invoked skill can call model-invoked ones. It can never reach another user-invoked one — that boundary is what keeps orchestration in one place.

## The main flow

Most work travels one route. Each step leaves a file rather than a conversation, so context can be cleared between them.

| Step                            | Skill                          | What it leaves behind                                     |
| ------------------------------- | ------------------------------ | --------------------------------------------------------- |
| Sharpen the idea                | `/grill-with-docs`             | Terms in `CONTEXT.md`, ADRs, and a written proposal        |
| Split it — multi-session builds | `/to-spec`, then `/to-tickets` | Delta specs, then tracer-bullet tickets in `tasks.md`      |
| Build it                        | `/implement`                   | A commit per ticket, driving `/tdd` and closing on `/code-review` |
| Close it                        | `/change-review`               | The archive — the only step that updates current behaviour |

Three situations merge onto that route rather than starting it: issues piling up (`/triage`), something broken (`/diagnosing-bugs`), and an effort too foggy to hold in one session (`/wayfinder`, which charts a map of decision tickets and rejoins at `/to-spec`).

The branches are the interesting part and a table cannot hold them — when the build is small enough to skip the split, when a question needs a prototype to answer, where to break context. **`/ask` is the router over all of it.** Type it when you are not sure which skill fits.

## What they are for

Each skill answers a failure mode that shows up repeatedly when building with agents:

- **Misalignment.** The agent builds the wrong thing because nobody stated the right thing precisely. The fix is an interview before any code — `/grill-me`, or `/grill-with-docs` where there is a repo to record the answers in.
- **No shared language.** Dropped into a project cold, an agent uses twenty words where the team uses one. A glossary in `CONTEXT.md` gives both sides the same nouns, which shortens every later session and makes naming consistent. `/domain-modeling` maintains it.
- **No feedback loop.** Without a signal that fails on the actual problem, an agent codes blind. `/tdd` runs red-green one slice at a time; `/diagnosing-bugs` refuses to theorise until a command reproduces the bug.
- **Entropy.** Agents accelerate mess as readily as progress. `/codebase-design` supplies the vocabulary for deep modules, and `/improve-codebase-architecture` surveys a codebase for the places worth deepening.

## Engineering

Daily code work.

**User-invoked**

- **[ask](./skills/engineering/ask/SKILL.md)** — Ask which skill or flow fits your situation. A router over the skills in this repo.
- **[grill-with-docs](./skills/engineering/grill-with-docs/SKILL.md)** — Grilling session that also builds your project's domain model, sharpening terminology into `CONTEXT.md` and recording hard-to-reverse decisions as ADRs, then closing by writing the change's proposal.
- **[triage](./skills/engineering/triage/SKILL.md)** — Move issues through a state machine of triage roles.
- **[improve-codebase-architecture](./skills/engineering/improve-codebase-architecture/SKILL.md)** — Scan a codebase for deepening opportunities, present them as a visual HTML report, then grill through whichever one you pick.
- **[setup-skills](./skills/engineering/setup-skills/SKILL.md)** — Configure this repo for the engineering skills (issue tracker, triage labels, domain doc layout). Run once per repo before using the other engineering skills.
- **[to-spec](./skills/engineering/to-spec/SKILL.md)** — Turn the agreed proposal into an OpenSpec change's delta specs, and publish one tracker issue pointing at it. No interview — just synthesizes what you've already discussed.
- **[to-tickets](./skills/engineering/to-tickets/SKILL.md)** — Break a change into tracer-bullet tickets, each declaring its blocking edges — written into the change's `tasks.md` as the source of truth, then cut into one issue each.
- **[implement](./skills/engineering/implement/SKILL.md)** — Build the work described by a spec or set of tickets, driving `/tdd` at pre-agreed seams and closing out with `/code-review` before committing.
- **[change-review](./skills/engineering/change-review/SKILL.md)** — The gate before a change is archived: reconcile `tasks.md` against the tracker, review the whole change on Coverage and Fidelity, then archive it into `openspec/specs/` — the one step that updates current behaviour.
- **[wayfinder](./skills/engineering/wayfinder/SKILL.md)** — Plan a huge chunk of work, more than one agent session can hold, as a shared map of decision tickets on the issue tracker — resolve them one at a time until the way to the destination is clear.

**Model-invoked**

- **[prototype](./skills/engineering/prototype/SKILL.md)** — Build a throwaway prototype to answer a design question — a single shareable HTML file for state/logic questions, or several radically different UI variations toggleable from one route.
- **[diagnosing-bugs](./skills/engineering/diagnosing-bugs/SKILL.md)** — Disciplined diagnosis loop for hard bugs and performance regressions: build a feedback loop that goes red on this bug → minimise → hypothesise → instrument → fix → regression-test.
- **[research](./skills/engineering/research/SKILL.md)** — Investigate a question against high-trust primary sources and capture the findings as a cited Markdown file in the repo, run as a background agent.
- **[tdd](./skills/engineering/tdd/SKILL.md)** — Test-driven development with a red-green-refactor loop. Builds features or fixes bugs one vertical slice at a time.
- **[domain-modeling](./skills/engineering/domain-modeling/SKILL.md)** — Actively build and sharpen a project's domain model — challenge terms against the glossary, stress-test with edge-case scenarios, keep `CONTEXT.md` a glossary, and route behaviour away from ADRs so they can stay frozen.
- **[writing-proposals](./skills/engineering/writing-proposals/SKILL.md)** — Open an OpenSpec change and write its proposal — the problem, the agreed solution, what was ruled out — plus the trade-offs half of `design.md`. No interview: it writes down what another skill already settled, which is what lets both `grill-with-docs` and `wayfinder` close the same way.
- **[codebase-design](./skills/engineering/codebase-design/SKILL.md)** — Shared discipline and vocabulary for designing deep modules: a lot of behaviour behind a small interface, placed at a clean seam, testable through that interface.
- **[code-review](./skills/engineering/code-review/SKILL.md)** — Two-axis review of the diff since a fixed point: **Standards** (does it follow the repo's coding standards, plus a Fowler smell baseline?) and **Spec** (does it faithfully implement the originating issue/spec?), run as parallel sub-agents so neither pollutes the other.
- **[resolving-merge-conflicts](./skills/engineering/resolving-merge-conflicts/SKILL.md)** — Work through an in-progress git merge or rebase conflict hunk by hunk, resolving by intent traced to each side's primary source, then finish the operation — never `--abort`.
- **[wizard](./skills/engineering/wizard/SKILL.md)** — Generate an interactive bash wizard that walks a human through steps only they can perform: provisioning infrastructure, setting up credentials or CI secrets, walking an unfamiliar third-party dashboard, or running a one-off migration or cutover.

## Productivity

General workflow tools, not code-specific.

**User-invoked**

- **[grill-me](./skills/productivity/grill-me/SKILL.md)** — Get relentlessly interviewed about a plan or design until every branch of the design tree is resolved.
- **[handoff](./skills/productivity/handoff/SKILL.md)** — Compact the current conversation into a handoff document so another agent can continue the work.
- **[teach](./skills/productivity/teach/SKILL.md)** — Teach the user a new skill or concept over multiple sessions, using the current directory as a stateful teaching workspace.
- **[to-questionnaire](./skills/productivity/to-questionnaire/SKILL.md)** — Turn a decision you can't answer alone into a Markdown questionnaire for the one person who can — filled in async, or together over a meeting. It grills you about the send (who it's for, what you need back), not the subject.
- **[wait-what](./skills/productivity/wait-what/SKILL.md)** — Fire this the moment a message doesn't land. The agent re-pitches it with the context you're missing, in plain English, using your `CONTEXT.md` vocabulary.

**Model-invoked**

- **[grilling](./skills/productivity/grilling/SKILL.md)** — Interview the user relentlessly about a plan, decision, or idea until every branch of the design tree is resolved. The reusable interview primitive behind `grill-me`, `grill-with-docs`, `triage`, `wayfinder` and `improve-codebase-architecture`.
- **[writing-for-agents](./skills/productivity/writing-for-agents/SKILL.md)** — Writing documents for agents: skills, AGENTS.md/CLAUDE.md, and any doc an agent reaches by a pointer.

## Working on this repo

Each skill is a folder holding `SKILL.md`, an `agents/openai.yaml` of Codex metadata, and any reference files it discloses. Every skill has a human-facing page under `docs/`. House rules live in `.agents/`, the repo's own vocabulary in `CONTEXT.md`, and the rules an agent needs in `CLAUDE.md` — which `AGENTS.md` symlinks to.

There is nothing to build, test, or install. Editing a `SKILL.md` changes the installed skill immediately, because the install is symlinks.

## Credits

These skills originate from [mattpocock/skills](https://github.com/mattpocock/skills) by Matt Pocock, MIT licensed. This repo is a detached fork: it tracks no upstream, ships no plugin, and carries its own changes on top. Those changes are copyright jackey8616 (Clooooode, Koli Mo) under the same licence — both notices are in [LICENSE](./LICENSE).
