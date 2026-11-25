# Writing cases

How to draft a skill's behaviour evals: what to test, the fixture each case runs in, the assertions that grade it, and the offline check that keeps fixtures honest. If the repo already has a skill with evals (`skills/*/tests/evals/`), read one first and follow its shape.

## Format

Copy the format from the "Test cases" section of `<sc>/references/schemas.md`: `prompt.md`, `case.yaml`, `graders/NN-few-words.md`, and, for a case that needs files, a scaffold script named in `case.yaml`. The format is strict, and `claude plugin eval` refuses a case that is off by one key. Cases go in `<skill>/tests/evals/<case>/`, not the `evals/` skill-creator uses: `tests/` is where this repo keeps what a skill needs only while it's being worked on, and the installer leaves it out. Run them with `--eval-dir tests/evals`.

## What to test

List the skill's rules that decide an outcome: a verdict, a stop, a refusal, a file written or left alone. Leave out wording rules nobody could grade. Then one case per rule, set up so that following the rule and breaking it give different results.

- Include a case where the skill should say yes. A skill can pass every failing case by failing everything.
- Keep each case to one rule, so a failing assertion names the rule that broke.
- Aim for five or so to start. Each costs a run per config per iteration.

## Fixtures

A case that works on a project builds it in its scaffold script. Build the smallest realistic one: a few files, the language's standard library, and its own test command (a Makefile `test` target), so the run finds it the way a user's repo would offer it. If the skill reviews changes, give it git history: the base committed on `main`, the change on a branch.

The run reads everything in the fixture, so put nothing in it you don't mean to test:

- Commit messages, names, and comments that tell the truth. A misleading one becomes a finding, and the grading drifts to it.
- No incidental mess: unsorted imports, a missing `.gitignore` for caches, a stray TODO. Runs report what they see.
- Names that don't hint at the case. The run should meet the project as a user's.

## Skills that change a project

When the skill's product is changes to a project (rules written, comments removed, a CI step added), a grader reading the diff can't tell whether the result works. Give the case a `post-check.sh` beside its `case.yaml`. `collect.py` runs it after the run, in a copy of the project, and saves its output as `post-check.md`. Print one line per check (`ok …` or `FAIL …`): the tests still pass, the new lint passes and fails on a planted violation, what must stay is still there. Make each check able to fail: run the script on the untouched fixture in `evals.test.sh` and confirm that the checks about the skill's work fail there. A check that holds before the skill has run proves nothing about it, unless it's about something that must be left as it was.

## Skills that ask mid-run

A run is a subagent: no one answers its questions. For a skill that stops to ask the user, write two cases. In one, the run stops at the question, and the assertions grade what it asked and what it did before asking. In the other, the prompt carries the answers up front, the way a user who knows the questions would type them, and the run goes to the end. If the skill has no word on answers given up front, that's worth reporting either way.

## Text-only skills

A skill that works on its arguments alone, one that rewrites a prompt or drafts a message, needs no fixture. Leave the scaffold out of `case.yaml`, and the run gets an empty directory. `collect.py` lists what the run created in it, as `project-state.md`.

Much of what such a skill makes is judged by taste: whether a rewrite is deeper, or a draft is better. Assert what can be checked: the shape of the reply, what it must not do (do the task it was asked to rewrite, add deliverables), and what each part is about. Leave the rest to the user, in the viewer, and say so in the report. An assertion that needs taste to grade gives a different verdict per grader.

## Prompts

`prompt.md` holds what the user would type. For a user-invoked skill that's `/<name> <arguments>`. In `allowed_tools`, also allow tools the skill shouldn't use. A read-only skill tested without Edit can't show it leaves Edit alone.

## Assertions

One checkable statement per grader file, about the result, not about where a workflow saves it. Every run reads the skill and saves its reply with tools, so "ran no commands" is false in every run. Say what else it must not do: "did nothing beyond reading the skill and saving its reply". Before keeping one, ask:

- Would a run that did nothing pass it? "The project is unchanged" alone, yes. Pair it with what the run must have done.
- Would a wrong answer that happened to land right pass it? A correct verdict for the wrong reason does. Also assert the reason.
- Can it be checked? A side effect on the project is checked against git (`repo-state.md`), not against what the run says. An order of steps ("ran the tests before reading the code") is checked in the transcript, with `focus: trace`.

The graders' `eval_feedback` after each iteration names the assertions that fail these questions. Tighten them before the next iteration.

## `tests/evals.test.sh`

It runs no model, so it runs everywhere, CI included. Two parts:

1. **Format**: every case folder loads. `scripts/check-evals.py <skill-dir>` checks it and prints `ok|<check>` or `bad|<check>|<why>` per line. Read those lines into the test's own pass and fail counts, as `skills/deepen/tests/evals.test.sh` does. In this repo, call it as `"$TESTS/../../skills-audit/scripts/check-evals.py"`.
2. **Premises**: build each case's fixture as a run would, and check that what the case claims about it is true. Which tests pass and which fail, on the base and on the change, what files appear, what a dependency import does. One check per claim, with a `case` branch per case name and a failure for a case with no branch. A case with no fixture still has a premise: its prompt is the one the case is about, for example no arguments in the case about none.

Then prove it can fail. In a copy, break one premise per case (make the new test exercise the fix, add an unknown setting, give the base the feature), and check that exactly that check fails. List the test in the repo's CLAUDE.md beside the others, which the repo's lint checks.
