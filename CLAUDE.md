Agent skills, written from scratch. Markdown, plus a few scripts and their tests.

Tests are offline. Run the one for whatever you changed, and `python3 lint-skills.py` for any change under `skills/`. CI (`.github/workflows/test.yml`) runs the lint and every test on each pull request and each push to `main`.

- `bash install.test.sh` — `install.sh`
- `bash lint-skills.test.sh` — `lint-skills.py`. Needs PyYAML (`pip install pyyaml`); only for working on this repo, since `install.sh` doesn't install it. It checks frontmatter, `agents/openai.yaml`, invocation set the same way in both, a README row per skill, the paths SKILL.md points at, and that every test sits where Layout says and is listed here. Its docstring lists each check. Description phrasing is checked only for the words "use when".
- `bash skills/codex-review/tests/detect.test.sh` — `skills/codex-review/scripts/detect.sh`
- `bash skills/deepen/tests/evals.test.sh` — the cases in `skills/deepen/tests/evals/`: that each loads, and that its prompt fits its case
- `bash skills/skills-audit/tests/scripts.test.sh` — `skills/skills-audit/scripts/prepare.py`, `collect.py`, `check-evals.py`, and `find-skill-creator.sh`
- `bash skills/test-first-code-review/tests/evals.test.sh` — the cases in `skills/test-first-code-review/tests/evals/`: that each loads, and that its fixture's tests pass and fail where the case says
- `bash skills/setup-annotation-guard/tests/tidy.test.sh` — `skills/setup-annotation-guard/scripts/tidy.py`
- `bash skills/setup-annotation-guard/tests/setup-annotation-guard.test.sh` — the ast-grep claims in `skills/setup-annotation-guard/SKILL.md`, and its `ledger.sh`, `remove.sh`, and `checks.sh`. Needs ast-grep on PATH or `AST_GREP=<path>`.

## Layout

One skill per directory: `skills/<name>/SKILL.md`, with `skills/<name>/agents/openai.yaml` beside it for Codex. The yaml is never optional. A skill's tests go in `skills/<name>/tests/`; `install.sh` leaves that directory out. `install.test.sh` sits beside `install.sh`.

A skill's behaviour evals go in `skills/<name>/tests/evals/`, one folder per case, in the layout `claude plugin eval` reads. A case that needs a repo to work in builds it with a `place-files.sh` scaffold. Each skill with evals has a `tests/evals.test.sh` that runs no model: it checks every case loads and every fixture is what its case says. The evals themselves are billed model runs, so they stay out of CI. Run them by hand from the repo root:

```bash
claude plugin eval skills/<name> --eval-dir tests/evals --scaffold --allow-tools Bash Write Edit --runs 1
```

To write a skill's evals, run them, and improve or benchmark it, use `/skills-audit <name>`.

## Invocation

Every skill is user-invoked or model-invoked. Set it in both harnesses or neither.

|               | `SKILL.md` frontmatter           | `agents/openai.yaml`                      |
| ------------- | -------------------------------- | ----------------------------------------- |
| User-invoked  | `disable-model-invocation: true` | `policy.allow_implicit_invocation: false` |
| Model-invoked | omit it                          | omit the `policy` block                   |

The description follows the choice. User-invoked: one human-facing line, no triggers. Model-invoked: keep trigger phrasing ("Use when the user…") so auto-invocation fires.

`agents/openai.yaml` shape:

```yaml
interface:
  display_name: "Name"
  short_description: "One line for the Codex picker"
# policy:                            # user-invoked only
#   allow_implicit_invocation: false
```

## Add, rename, remove a skill

Update the skill table in `README.md` in the same change.

## Install

`install.sh` downloads a tarball of `main` and copies skills in — no clone, no symlinks. Upgrades are explicit: the user re-runs it. Don't add auto-update.

Installed skills are copies of `main`, not of your checkout. To try a skill from a branch, run the installer with `SKILLS_REF=<branch>`, or symlink the skill dir by hand — the next install replaces that symlink.

## Gotchas

`AGENTS.md` symlinks to this file. Edit here, both harnesses follow.
