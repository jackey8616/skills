---
name: skills-replay
description: Replay merged PRs on a new model, with no skills and with your installed skills, to measure what the model can do on its own and what skills add, against the original PR.
disable-model-invocation: true
---

# Skills replay

`/skills-audit` asks whether a model follows a skill's rules, on small cases written for those rules. This asks something else: on real work, can the model meet the requirement on its own, and how much do skills add? It takes merged PRs and goes back to where each began: the base commit, the user's original prompt, no history after it. Then it runs the task again on the model you name, once with no skills at all (`plain`: the model's own ability) and once with every skill the user has installed (`skills`: the model as they work with it), and grades both, and the original PR, on the same evidence.

The task names no skill. The comparison is the model with skills against the model without, not one skill against none, so a PR made with any skill, or none, can be replayed. Over model releases, `plain` rising toward the original PR is the model getting able to do the work unaided, and the gap to `skills` is what the skills still add.

`$ARGUMENTS`: the repo (a path to a local clone) and its PR numbers, or paths to task files, then `--model <model> [<model>…]`, optionally `--runs <n>` (default 3) and `--replays <dir>`. Empty → ask which repo and PRs. Do nothing else first.

Task files and results live in one place for every repo: `replays/` at the top of the skills repo this skill comes from, `<replays>` from here on. Not in `skills/`: an install copies `skills/`, and the `skills` arm copies the install, so a task file there would hand the arm the PR's tests and rubric. `<replays>` is `--replays <dir>` if given, else `./replays` when the current directory is a clone of the skills repo. Neither → ask for the clone's path along with anything else you need to ask, and write no task file until you have it. The skills repo is public, so everything in `<replays>` is too: say so the first time you write there.

The `skills` arm copies `~/.claude/skills` as it is (`--skills-dir <dir>` for another set). The report names the skills loaded and a digest of their files: two dates with different digests had a different skill set as well as a different model.

## 1. Set up

- **The base directory**, `<base>`: your scratchpad, or a temp directory, never inside a repository. Every run has its own project copy and config directory, and they fill it.
- `replay.py` needs PyYAML (`pip install pyyaml`), git, and the `claude` CLI: `python3 "${CLAUDE_SKILL_DIR}/scripts/replay.py" doctor` checks they're there. Missing → say what, and stop.

## 2. Task files

Each PR needs `<replays>/<repo>/<repo>-pr<N>/task.yaml`, where `<repo>` is the repo's name. One exists → read it, and go to section 3. None → read `references/task-file.md` and write it. Most of it comes from git and `gh`. Four parts can't come from those alone, and each needs the user's OK before any run:

- **prompt**: the user's exact words. Found in a session, the PR body, or from the user. Never written by you: a prompt you wrote measures your wording, not the user's task.
- **plain_prompt**: the same request with no slash command, when the prompt starts with one. It states what the user wanted, not the skill's method. A plain prompt that spells out the skill's steps hands the plain arm the skill, and the comparison then shows nothing.
- **hidden_tests** and **test_command**: the PR's own tests, and the command that runs them.
- **rubric**: 3–6 things the change had to get right, from the PR's description and review comments.
Don't ask which skill the PR was made with: the replay doesn't need it.

Show the four together, per PR, with where each came from. A PR whose session took several user turns: ask whether to fold the turns into one prompt or drop the PR. A replay of the first message alone grades the model on a task the user never gave it.

The files in `<replays>` are the user's to commit. Say where they are and leave the commit to their word. In a cloud session, say too that they're lost with the container unless committed and pushed.

One PR tells little: a model can have a good or bad day on any one task. Three or more PRs, of different kinds of work, tell more. Say so if the user names one.

## 3. Check without a model

```bash
python3 "${CLAUDE_SKILL_DIR}/scripts/replay.py" run <task.yaml> <base>/dry --repo <repo> --model none --runs 0
python3 "${CLAUDE_SKILL_DIR}/scripts/replay.py" summarize <base>/dry/<task-id>/*
```

`--runs 0` builds the base and the reference and runs their checks, with no model call. Read the result before spending:

- **The hidden tests pass on the base** → they can't tell a fix from no change. Find the PR's tests that fail without it, or lean on the rubric and say so.
- **The original PR fails its own hidden tests, or doesn't apply** → `setup` or `test_command` is wrong, or `base` isn't where the PR began. Fix the task file and check again.
- **A check fails on the reference** → it was failing then too. Drop it, or the arms are graded on a bar the PR didn't meet.

## 4. Run

Count first: PRs × models × arms × runs model runs, each a full agent session of up to `max_turns`, plus two grader calls per run (section 5). Tell the user the count and wait for their OK.

Then, before the first run, two checks that sections 2 and 3 didn't need:

- **skill-creator**: grading and the blind comparison are its agents. Find it with skills-audit's finder, which installs with this skill:

  ```bash
  bash "${CLAUDE_SKILL_DIR}/../skills-audit/scripts/find-skill-creator.sh"
  ```

  It prints skill-creator's directory, `<sc>` from here on. Nothing printed → tell the user this needs skill-creator installed, or `SKILL_CREATOR=<dir>`, and stop.
- **Sign-in**: a run can't use the user's config, so check it can sign in without it. It's one tiny billed call:

  ```bash
  python3 "${CLAUDE_SKILL_DIR}/scripts/replay.py" doctor --live
  ```

  Not ready → pass on what it printed and stop.

One command per PR and model, in the background:

```bash
python3 "${CLAUDE_SKILL_DIR}/scripts/replay.py" run <task.yaml> <base> --repo <repo> --model <model> --runs <n> [--skills-dir <dir>] [-j 2]
```

The model is the exact id the user gave, not a family name. A name like `opus` moves to a new model on its own, and two dates would then compare different models under one label. `-j` runs that many sessions at once. They share one rate limit, so keep it low. The script prints the label directory, `<label>` from here on (`<base>/<task-id>/<YYYY-MM-DD>-<model>`). The module docstring lists what each run writes.

Don't read the runs' project copies. They're gone when a run ends. What matters is in its run directory: `changes.diff`, `checks.json`, `reply.md`, `transcript.md`.

## 5. Grade

Two subagents per run, started together once a PR's runs are done. Start one more for the reference, so the rubric is checked on the original PR too.

**Rubric**, one per run and one for `<label>/reference/`:

```
You are a grader. Read <sc>/agents/grader.md and follow it.
- expectations: the `rubric` in <task.yaml>
- transcript_path: R/transcript.md (for the reference: none, it was not a model run)
- outputs_dir: R (changes.diff is the change, checks.json the PR's hidden tests and checks run on it, reply.md the final reply). Judge each expectation on the change itself; the reply's claims about it are not evidence.
Write R/grading.json with `text`, `passed`, `evidence` in `expectations`, and a `summary`.
```

**Blind comparison** with the original PR, one per run:

```
You are a blind comparator. Read <sc>/agents/comparator.md and follow it.
- output_a_path: R/compare/A
- output_b_path: R/compare/B
- eval_prompt: the `prompt` in <task.yaml>
- expectations: the `rubric` in <task.yaml>
Write R/compare/comparison.json.
```

Don't read `<label>/.keys/` before the comparisons are in, and never pass it to a grader. Which side is the original PR is all the blinding is.

## 6. Record and compare

```bash
python3 "${CLAUDE_SKILL_DIR}/scripts/replay.py" summarize <label> [<label>…]
```

It prints one table per PR and model: the original PR, then each arm, with hidden tests, checks and rubric passed, wins, ties and losses against the original PR, mean cost, turns and minutes, and runs that leaked. Under it go the warnings: runs that may have seen the PR, didn't finish, or changed nothing.

Save it to `<replays>/<repo>/results/<YYYY-MM-DD>-<model>.md`, one file per repo, model and date, holding every PR of that repo run that day. Then compare with the earlier files there in one table: PRs down the side, then `plain` and `skills` per model or date across, with each date's skills digest. Only these summaries go in `<replays>`. The run directories stay in `<base>`.

Read the gap between the arms, not either score alone:

- **plain meets the PR's bar** (its hidden tests, checks and rubric) → the model can do this kind of work on its own.
- **plain falls short, skills meets it** → the skills carry the model here. The transcripts show which skill fired and what it changed.
- **skills ≈ plain, on most PRs** → the model now does unaided what the skills taught. The skills are candidates to cut down or retire. One PR can't show this: several can.
- **skills below plain** → the skills get in the way now. The transcripts show which instruction: a step the model would have skipped, a check it now makes anyway.
- **both below the original PR** → the new model is worse at this task, or the original needed the user's steering in later turns. The transcript of the original session settles which.
- **plain across dates** → the trend in the model's own ability. It doesn't depend on the skills, so it compares across any two dates.
- **The skills digest changed between two dates** → the skill set changed as well as the model. Read the `skills` column and the gap against that.

Before you put a change down to the model, read that PR's runs: a leak, a flaky test, or a broken `setup` looks the same in a score. Leave runs with leaks out of the comparison and say how many.

## 7. Report

```
## Skills replay — <repo>, <model(s)>
<PRs>, <arms>, <runs> run(s) each. Workspace: <base>

<summarize's tables>

## Against earlier models
<PR × model/date table, or "first replay">

## What it shows
- <what plain shows about the model on its own, and what the gap to skills shows, with how many PRs back each>

## Left out
- <runs dropped for leaks or failures, and tasks skipped, with why>

Results file: <replays>/<repo>/results/<file>
```

What to do about the skills is the user's call, with your recommendation first. Retiring or rewriting one is a change in the skills repo, and `/skills-audit` is how to make it.
