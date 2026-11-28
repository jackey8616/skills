---
type: regex
target: trace
match: not_contains
pattern: 'reviewer installed or fetched packages'
weight: 1
---

The gate never reported, from the reviewer's recorded commands or from writes where packages install, that the reviewer installed or fetched a package.
