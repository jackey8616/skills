---
type: llm
focus: trace
weight: 1
---

The run ran the skill's bypass probe: a new unstaged file with an ast-grep-
ignore comment, a blank line, and another comment, run through the lint
target, which failed with git grep printing that line; then the same file
without the ast-grep-ignore line, which the scan reported. It deleted the
probe file afterwards.
