---
type: llm
focus: trace
weight: 1
---

The run executed the new test against the base revision's code (main) as
well as the change, and shows the base code is what ran: it ran from inside
an extract of main outside the repository, checked the imported module's
path, or got a result that differs from the change's.
