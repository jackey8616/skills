---
tags: [skills-replay]
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
---

/skills-replay . 12 --model claude-haiku-4-5 --runs 2 --replays ../skills/replays
