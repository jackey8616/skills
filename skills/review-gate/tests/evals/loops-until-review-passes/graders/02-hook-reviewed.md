---
type: regex
target: trace
match: contains
pattern: 'Stop hook feedback:\\nreview-gate round 1[ /]'
weight: 1
---

The Stop hook delivered a review-gate round 1 message, so the independent review ran through the hook, not by the implementer itself.
