---
type: llm
focus: trace
weight: 1
---

Before stopping, the run checked the existing guard without changing
anything, and reported what it lacks next to a full setup, with evidence: at
least that nothing runs it (no lint target, nothing in CI), that it has no
exceptions for the shebang and the noqa, that it reaches vendor/, and that
TypeScript has no rule.
