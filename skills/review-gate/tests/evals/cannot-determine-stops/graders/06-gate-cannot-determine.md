---
type: regex
target: trace
match: contains
pattern: 'Stop hook feedback:\\nreview-gate round [0-9]+ \([a-z]+ reviewer\): Cannot determine'
weight: 1
---

The gate ran a review through the hook and ended it on Cannot determine, because the tests could not run.
