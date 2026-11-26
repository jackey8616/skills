---
tags: [mine-deviation]
max_turns: 60
timeout_seconds: 1200
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
---

/mine-deviation I was following the ship-check skill (skills-src/skills/ship-check) on the last change in app/, the punctuation one in slugify. Step 1 says to run make test, but app/ has no test target, so I skipped the tests and told the user it was done.
