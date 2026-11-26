# skills

Agent skills for Claude Code and Codex.

## Install or upgrade

```bash
curl -fsSL https://raw.githubusercontent.com/jackey8616/skills/main/install.sh | bash
```

Copies every skill into `~/.claude/skills` and `~/.agents/skills`, and prints what it installed, upgraded, or removed. Re-run it to upgrade — nothing updates on its own. Start a new session afterwards.

Pin a version with `SKILLS_REF`:

```bash
curl -fsSL https://raw.githubusercontent.com/jackey8616/skills/main/install.sh | SKILLS_REF=<tag-or-commit> bash
```

Uninstall:

```bash
curl -fsSL https://raw.githubusercontent.com/jackey8616/skills/main/install.sh | bash -s -- --uninstall
```

The installer only touches skills it installed, with one exception: a symlink at a skill's path (a hand-linked dev checkout) is replaced with a copy. A real directory of the same name that it didn't create is skipped, never overwritten.

### Claude Code on the web

A cloud session runs in a fresh container, so the skills are installed per container, not once. Put the installer in your cloud environment's setup script: in the cloud environment menu in the session's title bar, choose Edit, then Setup script. It runs before Claude starts in every new session on that environment, whatever the repository:

```bash
curl -fsSL -H 'Accept: application/vnd.github.raw' \
  https://api.github.com/repos/jackey8616/skills/contents/install.sh | bash || true
```

It fetches the same `install.sh` through the GitHub API rather than `raw.githubusercontent.com`. With limited network access, the cloud proxy refuses `raw.githubusercontent.com`, while `api.github.com` and `codeload.github.com`, where the installer downloads from, get through. `|| true` is there because a failing setup script stops the session from starting. A failed install should cost you the skills, not the session. Pin a version as above, with `SKILLS_REF=<tag-or-commit>` before `bash`.

Each new container installs `main` as it is then. To upgrade a session that's already running, run the command in it and start a new session. See [cloud environments](https://code.claude.com/docs/en/cloud-environments) for the setup script and network access.

Test the installer (offline, throwaway `$HOME`):

```bash
bash install.test.sh
```

## Skills

Model-invoked — the agent uses it when your request fits. You can also type the name.

| Skill | What it does |
| ----- | ------------ |
| [`test-first-code-review`](skills/test-first-code-review/SKILL.md) | Review a change, fix or feature, by running its tests first, then reading the code. Never touches the codebase. |
| [`codex-review`](skills/codex-review/SKILL.md) | Claude implements, Codex reviews with `test-first-code-review`, Claude fixes; up to ten rounds. Uses a Herdr reviewer tab when available. |
| [`mine-deviation`](skills/mine-deviation/SKILL.md) | When an agent notices it didn't follow a skill, it drafts an issue for the skill's maintainer and files it once you say yes. |

User-invoked — type the name to run it.

| Skill | What it does |
| ----- | ------------ |
| [`deepen`](skills/deepen/SKILL.md) | Rewrite a prompt into a deeper version of the task, not a bigger one. |
| [`setup-annotation-guard`](skills/setup-annotation-guard/SKILL.md) | Ban code comments in a repo with an ast-grep rule that allows only tool directives, wire it into lint and CI, and remove the comments already there. |
| [`skills-audit`](skills/skills-audit/SKILL.md) | Run a skill's behaviour evals in fresh agents, grade them, and improve the skill with you round by round, or benchmark it across models. Uses skill-creator's grader and viewer. |
| [`skills-replay`](skills/skills-replay/SKILL.md) | Replay merged PRs on a new model, once with no skills and once with your installed skills, and grade both against the original PR: its hidden tests, its checks, a rubric, and a blind comparison. Tracks per model what it can do on its own and what skills add. |
