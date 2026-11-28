---
tags: [review-gate]
max_turns: 60
timeout_seconds: 1800
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
---

/review-gate divide(a, 0) must raise ValueError("division by zero") instead of ZeroDivisionError, with a unittest that covers it. Only the uncommitted changes are this work.
