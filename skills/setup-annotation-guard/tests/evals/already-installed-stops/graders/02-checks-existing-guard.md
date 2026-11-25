---
type: llm
focus: trace
weight: 1
---

Before stopping, the run checked the existing guard without changing
anything, and reported what it lacks next to a full setup, with evidence:
that nothing runs it (no lint target, nothing in CI); that it has no
exceptions, naming the shebang in scripts/export.py and the noqa in
notes/store.py it flags and that its fix would delete them; that it reaches
vendor/; and that TypeScript has no rule.
