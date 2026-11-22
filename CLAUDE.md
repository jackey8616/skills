Agent skills, written from scratch. Markdown only.

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

## Gotchas

`AGENTS.md` symlinks to this file. Edit here, both harnesses follow.
