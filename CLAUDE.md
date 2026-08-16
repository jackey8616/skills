Skills are organized into two bucket folders under `skills/`:

- `engineering/` — daily code work
- `productivity/` — daily non-code workflow tools

Every skill must live in one of them, and must have a reference in the top-level `README.md` with the skill name linked to its `SKILL.md`. There is no beta, retired, or unpromoted bucket: a skill is either in the set or deleted.

Each bucket folder has a `README.md` that lists every skill in the bucket with a one-line description, with the skill name linked to its `SKILL.md`. Both bucket `README.md`s and the top-level `README.md` group entries into **User-invoked** and **Model-invoked**.

Every skill also has a human-facing docs page at `docs/<bucket>/<skill-name>.md` — the docs tree mirrors the two bucket folders under `skills/`. When you add, rename, or change the behaviour of a skill, create or re-sync its docs page following [.agents/writing-docs.md](./.agents/writing-docs.md). A finished page carries four sections — **What it does**, **When to reach for it**, **Common questions**, **It's working if** — and `writing-docs.md` holds the template, the section order, and where to hunt for the questions.

Every `SKILL.md` is either user-invoked (`disable-model-invocation: true` plus `policy.allow_implicit_invocation: false` in `agents/openai.yaml`, reachable only by the human) or model-invoked (model- or user-reachable). See [.agents/invocation.md](./.agents/invocation.md).

[`ask-matt`](./skills/engineering/ask-matt/SKILL.md) is the router that maps every user-reachable skill and how they relate. The same trigger that re-syncs a docs page applies to it: whenever you add, rename, remove, or change how a user-reachable skill fits the flows, re-read `ask-matt`'s `SKILL.md` and update it so the map stays accurate — a new skill it never mentions, or a stale one it still routes to, is a router that lies.

To (re)link every skill into the local harness skill directories (`~/.claude/skills`, `~/.agents/skills`), run `scripts/link-skills.sh`. Each entry is a symlink into this repo, so a `git pull` keeps installed skills current; re-run the script after adding, removing, or renaming a skill. That script is the only install route — this repo is not published as a plugin and ships no release tooling.
