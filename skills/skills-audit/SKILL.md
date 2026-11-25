---
name: skills-audit
description: Audit a skill by running its behaviour evals, improve it with you round by round, or benchmark it across models.
disable-model-invocation: true
---

# Skills audit

A skill is instructions for a model, and it works only if a model reading it does what it says. Reading the skill can't show that; running it can. This audit turns each rule of the skill into a case, runs the skill on every case in a fresh agent, grades what happened against evidence, and reports. It changes the skill only where the user decides, then measures again against the version before.

`$ARGUMENTS`: the skill, by path or name, then optionally `benchmark <model> [<model>…]`. Empty → ask which skill. Do nothing else first.

- No `benchmark` → an audit: sections 1–6, then section 7 for as long as the user wants changes.
- `benchmark <models>` → sections 1, 3 and 8. Every case must already exist and pass its offline check.

## 1. Set up

- **The skill**: a path, or `skills/<name>/` in the current repo, else `~/.claude/skills/<name>/`. No `SKILL.md` there → ask.
- **skill-creator**: grading, the benchmark, and the viewer are skill-creator's own tools, not copies:

  ```bash
  bash "${CLAUDE_SKILL_DIR}/scripts/find-skill-creator.sh"
  ```

  It prints skill-creator's directory, `<sc>` from here on. Nothing printed → tell the user this needs skill-creator installed, or `SKILL_CREATOR=<dir>`, and stop.
- **The base directory**, `<base>`: your scratchpad, or a temp directory, never inside a repository. The workspace fills with runs, transcripts, and viewer pages; in a repo they'd show up in every diff, and a repo lint reads any directory under `skills/` as a skill. Tell the user where it is: it goes when the session does.
- `prepare.py` needs PyYAML (`pip install pyyaml`).

## 2. Structure

The repo's own skill lint, if it has one (`python3 lint-skills.py`, or what its CLAUDE.md or AGENTS.md names) → run it. Otherwise check by hand: frontmatter `name` matches the directory, `description` is present, `SKILL.md` is under 500 lines, every file it points at exists, and every script has a test. Failures go in the report. Don't fix them unasked.

## 3. Cases

Cases live in `<skill>/tests/evals/<case>/`, one folder each, in the layout `claude plugin eval` reads. Beside them, `<skill>/tests/evals.test.sh` runs no model. It checks that each case loads, with `scripts/check-evals.py`, and that its fixture is what the case says. A case whose fixture drifted grades the model on the wrong question.

- **None yet** → read `references/writing-cases.md`. List the skill's rules that decide an outcome, and propose one case per rule: the name, what the case sets up, and what a run that follows the skill does. Wait for the user's OK. Then write the cases, their fixtures, and `evals.test.sh`, and run it.
- **Some exist** → run `evals.test.sh` first; failing → stop and report. Then match the skill's rules to cases. A rule no case reaches goes in the report under Coverage, with a proposed case.

## 4. Run an iteration

Iteration 1 runs only the skill as it is (`with_skill`). Before any edit the old version is the same skill, so a baseline would double the cost and show nothing. From iteration 2 on, `old_skill` runs too: by default the snapshot `prepare.py` took at iteration 1, `<base>/<name>-workspace/skill-snapshot/`. To compare against the previous iteration instead, snapshot that version yourself and pass it. Say which you used.

Each iteration costs one run per case and config, plus graders. Tell the user the count before starting.

```bash
python3 "${CLAUDE_SKILL_DIR}/scripts/prepare.py" <skill-dir> <base> <N> [--old <snapshot-dir>]
```

It builds each run's project with the case's scaffold, copies the skill without `tests/`, and writes `runs.json` in the iteration's directory, `<it>` from here on (`<base>/<name>-workspace/iteration-<N>`). Every path a run sees is a random id. A run that can tell it's an eval, or which case it is, or what the graders expect (all sitting in `tests/evals/`), behaves differently from a real user's run.

Start every run in one turn, one background subagent each. Each run's prompt is its `executor_prompt` from `runs.json`: send it exactly as it is, with nothing added. It names the skill copy, the project, the user's prompt, what `$ARGUMENTS` holds, a temp directory, and where to save the reply, and nothing about the case. Note each run's transcript path, which the subagent tool gives when it starts the run.

As each run finishes, collect it at once. The completion notice is the only place its token count and duration appear:

```bash
python3 "${CLAUDE_SKILL_DIR}/scripts/collect.py" <it> <case> <config> --tokens <n> --ms <n> --transcript <path>
```

Don't read transcripts yourself. They're long, and `collect.py` writes the trimmed `transcript.md` the graders need. `outputs/repo-state.md` (a project that's a git repo) or `outputs/project-state.md` (one that isn't) comes from the disk, not from the run: it is the evidence for whether the run changed the project.

No subagent tool (Codex) → run the cases with section 8's command at the current model instead, one config per run, and say that the `old_skill` comparison isn't available.

## 5. Grade and show

One grader subagent per case, grading every config of that case, each on its own evidence:

```
You are a grader. Read <sc>/agents/grader.md and follow it, once for each run below. Grade each on its own evidence; don't compare them.
- expectations: the `assertions` in <it>/<case>/eval_metadata.json
- runs: <it>/<case>/<config>/ for each config there (with_skill alone in iteration 1). For each run R: transcript_path R/transcript.md; outputs_dir R/outputs (reply.md is the final reply; repo-state.md or project-state.md is the project's state after the run, read from the disk, and the primary evidence for any expectation about changes to it). Write R/grading.json with `text`, `passed`, `evidence` in `expectations`, a `summary`, and `eval_feedback` when you find a real gap.
Your final message: per run, PASS/FAIL per expectation, and any eval_feedback.
```

Then:

```bash
cd <sc> && python3 -m scripts.aggregate_benchmark <it> --skill-name <name>
cd <sc> && python3 eval-viewer/generate_review.py <it> --skill-name <name> --benchmark <it>/benchmark.json --static <base>/<name>-workspace/review-iteration-<N>.html [--previous-workspace <base>/<name>-workspace/iteration-<N-1>]
```

Before generating the viewer, add to `notes` in `benchmark.json` what the pass rate hides:

- One run per case and no baseline → 100% says the skill did what the cases ask, not that the cases tell a good run from a bad one.
- Which cases changed between configs, and whether that's the change this iteration made.
- Assertions the graders say a do-nothing or wrong-but-lucky run would pass.
- Runs that handled the same situation differently. Two runs taking different paths through one rule usually means the skill doesn't say. That's a skill gap, not noise.

Send the viewer page to the user as soon as it's written, before your own write-up, so they can read the runs first.

## 6. Report

```
## Skills audit — <name>, iteration <N>
<configs>, <runs per case> run(s) each. Workspace: <path>

| Case | with_skill | old_skill |
| ---- | ---------- | --------- |

## Structure
- <lint result, or each failure>

## Coverage
- <rule with no case> — <proposed case>

## Skill gaps — your call
1. <what the skill leaves open> — <case: what each run did> — <options, recommended first>

## Weak assertions
- <case>/<assertion> — <what would pass it wrongly>

Viewer: <path>
```

A gap the user must decide goes to them as a question, with your recommendation first. Weak assertions and coverage gaps are yours to fix in section 7. Name them here.

## 7. Improve

Only what the user decided. Change the skill so it explains why, and generalise: the cases are a handful of examples of a skill that runs thousands of times, so a wording that fits the fixtures and nothing else makes it worse. In the same change, update cases whose expected outcome the decision moved, tighten the weak assertions, and run `evals.test.sh`. Read every assertion against the changed skill, not just the ones the decision names: one written for the old wording can fail a run that follows the new one. In deepen's audit, "the reply ends with the rewrite" outlived a change that put suggestions after it. Leave the commits to the user's word.

Then run the next iteration with `--old` (section 4). Read the result against the change:

- The cases the change was for differ between configs, the new skill passing → the change works and the cases can tell.
- They don't differ → either the change didn't take, or the case can't see it. Find which before trusting either version.
- Any other case differs → a regression, or a noisy case. Rerun that case before blaming the change.

Stop when the user is satisfied, or when nothing fails and no gap is open. Also stop when each iteration's findings have shrunk to rare edge cases: say so and recommend stopping, since another round costs as much as the first.

## 8. Benchmark models

Comparing models takes the CLI, which runs each case on the model you name:

```bash
claude plugin eval <skill-dir> --eval-dir tests/evals --scaffold --allow-tools Bash Write Edit --trust-plugin \
  --model <model> --runs 3 --ablation none --no-publish --json <base>/bench-<model>.json --report <base>/bench-<model>.html
```

- `--runs 3`: one run per model can't tell a model from noise.
- `--ablation none`: this compares models on the same skill, not the skill against no skill. For a user-invoked skill the no-skill arm can't even run the command.
- `--scaffold` and `--trust-plugin` run the case scripts as the user. Use them only on cases that belong to this skill.
- Cost: cases × runs × models, every one a billed run. Say the number and get the user's OK first.

Per model, write `<skill>/tests/evals/benchmarks/<YYYY-MM-DD>-<model>.md`: date, model, `claude --version`, the skill's commit (`git rev-parse --short HEAD`), runs per case, each case's score, and the overall score, all read from the `--json` output. Then compare with the earlier files in `benchmarks/`, as a model × case table. Before putting a drop down to the model, read that case's runs in the report: a flaky case or a changed fixture looks the same in a score. Only these summaries belong in the repo; the full output stays in `<base>`.
