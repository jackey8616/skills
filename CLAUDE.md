Agent skills, written from scratch. Markdown, plus `install.sh` and its tests.

Test: `bash tests/install.test.sh` — offline, run it after any change to `install.sh`.

## Layout

One skill per directory: `skills/<name>/SKILL.md`, with `skills/<name>/agents/openai.yaml` beside it for Codex. The yaml is never optional.

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
