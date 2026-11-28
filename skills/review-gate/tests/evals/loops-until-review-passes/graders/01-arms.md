---
type: regex
target: trace
match: contains
pattern: '```review-gate\\nsource: [^<][^`]*?\\nbase: [^<][^`]*?\\nrequirement:\\n[^<`][^`]*?division by zero'
weight: 1
---

A reply ends with a fenced review-gate block whose source, base and requirement are filled in (not the template), the requirement holding the divide-by-zero requirement. Regex over the trace: the llm judge sees only the start and end of a long trace, and the block comes mid-run.
