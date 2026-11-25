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

## Prompts

`prompt.md` holds what the user would type. For a user-invoked skill that's `/<name> <arguments>`. In `allowed_tools`, also allow tools the skill shouldn't use. A read-only skill tested without Edit can't show it leaves Edit alone.

## Assertions

One checkable statement per grader file, about the result, not about where a workflow saves it. Before keeping one, ask:

- Would a run that did nothing pass it? "The project is unchanged" alone, yes. Pair it with what the run must have done.
- Would a wrong answer that happened to land right pass it? A correct verdict for the wrong reason does. Also assert the reason.
- Can it be checked? A side effect on the project is checked against git (`repo-state.md`), not against what the run says. An order of steps ("ran the tests before reading the code") is checked in the transcript, with `focus: trace`.

The graders' `eval_feedback` after each iteration names the assertions that fail these questions. Tighten them before the next iteration.

## `tests/evals.test.sh`

It runs no model, so it runs everywhere, CI included. Two parts:

1. **Format**: every case folder loads. That means `prompt.md` has only known settings and a prompt that invokes the skill, `case.yaml` has `schema_version: "1.1"` quoted and a `name` matching its folder, the scaffold exists, and every grader has its header and a statement.
2. **Premises**: build each case's fixture as a run would, and check that what the case claims about it is true. Which tests pass and which fail, on the base and on the change, what files appear, what a dependency import does. One check per claim, with a `case` branch per case name and a failure for a case with no branch.

Then prove it can fail. In a copy, break one premise per case (make the new test exercise the fix, add an unknown setting, give the base the feature), and check that exactly that check fails. List the test in the repo's CLAUDE.md beside the others, which the repo's lint checks.
