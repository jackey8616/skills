---
tags: [setup-annotation-guard]
max_turns: 150
timeout_seconds: 3600
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
---

/setup-annotation-guard My answers to your questions, so you don't need to ask: ban Python docstrings and doc comments everywhere; remove the comments in files ast-grep can't parse, once, by hand; pin ast-grep 0.39.5 with an install step in CI only.
