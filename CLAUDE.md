Agent skills. Markdown only. No build, no tests, no dependencies, nothing to run.

## Where things live

Two buckets under `skills/` — `engineering` and `productivity`. Those two, no others.
`.agents/` — house rules and ADRs.
`CONTEXT.md` — this repo's vocabulary. Write skills in its words.

## Add, rename, remove a skill

Five things move together. Miss one, the repo lies.

1. `skills/<bucket>/<name>/SKILL.md`
2. `skills/<bucket>/<name>/agents/openai.yaml` — Codex metadata, never optional
3. `docs/<bucket>/<name>.md` — template and section order in [.agents/writing-docs.md](.agents/writing-docs.md)
4. `skills/<bucket>/README.md` and top-level `README.md` — both list every skill, grouped User-invoked / Model-invoked, name linked to its `SKILL.md`
5. `skills/engineering/ask-matt/SKILL.md` — routes every user-reachable skill. Re-read it, fix the map. A stale route is a router that lies.

Done when one `SKILL.md` has one docs page of the same name, and both READMEs carry it.

## Invocation

Every skill is one or the other. Set it in both harnesses or neither.

|                | `SKILL.md` frontmatter            | `agents/openai.yaml`                    |
| -------------- | --------------------------------- | --------------------------------------- |
| User-invoked   | `disable-model-invocation: true`  | `policy.allow_implicit_invocation: false` |
| Model-invoked  | omit it                           | omit the `policy` block                 |

The description follows the choice. User-invoked reads human-facing, one line, no triggers. Model-invoked keeps trigger phrasing ("Use when the user…") so auto-invocation fires.

A user-invoked skill reaches model-invoked skills only. Rest in [.agents/invocation.md](.agents/invocation.md).

## Writing any of it

Load `/writing-for-agents` before editing a `SKILL.md`, this file, or any doc an agent reaches by pointer. House style lives in that skill, not here.

## Install

`scripts/link-skills.sh` symlinks every skill into `~/.claude/skills` and `~/.agents/skills`. The only route — no plugin, no package, no release.

Symlinks are live. Edit `skills/engineering/tdd/SKILL.md` and `/tdd` changes now, in every repo on this machine. Re-run the script after add, rename, remove.

## Gotchas

`AGENTS.md` symlinks to this file. Edit here, both harnesses follow.

Detached fork of `mattpocock/skills`. Docs pages still carry upstream's absolute `aihero.dev` and `github.com/mattpocock/skills` links. Some 404 — fork-only skills (`change-review`, `writing-proposals`) never existed upstream. Write repo-relative links; fix stale ones in pages you touch.

ADR numbers are never reused. `0002` went with the plugin. The gap is correct.
