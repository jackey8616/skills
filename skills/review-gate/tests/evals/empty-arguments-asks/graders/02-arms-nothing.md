---
type: regex
target: trace
match: not_contains
pattern: '```review-gate\\nsource: [^<]'
weight: 1
---

No reply holds a filled-in review-gate block: with no requirement, nothing arms the gate.
