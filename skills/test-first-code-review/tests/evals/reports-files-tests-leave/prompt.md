---
tags: [test-first-code-review]
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
---

/test-first-code-review parse_duration must read minutes: parse_duration("1h30m") returns 5400, not 3630.
