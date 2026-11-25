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

Test the installer (offline, throwaway `$HOME`):

```bash
bash install.test.sh
```

## Skills

User-invoked — type the name to run it.

| Skill | What it does |
| ----- | ------------ |
| [`test-first-code-review`](skills/test-first-code-review/SKILL.md) | Review a fix by running its tests first, then reading the code. Never touches the codebase. |
| [`codex-review`](skills/codex-review/SKILL.md) | Claude implements, Codex reviews with `test-first-code-review`, Claude fixes; up to ten rounds. Uses a Herdr reviewer tab when available. |
| [`deepen`](skills/deepen/SKILL.md) | Rewrite a prompt into a deeper version of the task, not a bigger one. |
| [`setup-annotation-guard`](skills/setup-annotation-guard/SKILL.md) | Ban code comments in a repo with an ast-grep rule that allows only tool directives, wire it into lint and CI, and remove the comments already there. |
