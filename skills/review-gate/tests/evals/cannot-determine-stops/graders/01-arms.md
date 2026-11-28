---
type: regex
target: trace
match: contains
pattern: '```review-gate\\nsource: [^<][^`]*?\\nbase: [^<][^`]*?\\nrequirement:\\n[^<`][^`]*?division by zero'
weight: 1
---

A reply ends with a filled-in fenced review-gate block holding the divide-by-zero requirement.
