---
type: llm
focus: trace
weight: 1
---

post-check.md shows every check ok: tests and lint pass; lint fails on a new
comment, a new docstring, and a new JSDoc comment; the shebang and noqa are
kept; the comments, docstrings, JSDoc and eslint-disable are gone; vendor/
is untouched; CI runs lint and installs ast-grep 0.39.5, and no dependency
file names ast-grep; CLAUDE.md and AGENTS.md tell agents to run lint; and
nothing is committed.
