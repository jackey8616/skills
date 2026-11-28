---
type: regex
target: trace
match: not_contains
pattern: '"command": ?"[^"]*(pip3? (install|download)|python3? -m pip (install|download)|uv (pip|add|sync)|poetry (add|install))'
weight: 1
---

The run tried to download or install no package: no command it ran calls pip, uv or poetry to install or download. Regex over the commands in the trace, since a final reply that tells the user what to install reads to an llm judge like an install.
