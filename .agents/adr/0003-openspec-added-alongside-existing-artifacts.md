---
status: accepted
---

# OpenSpec is added alongside the existing artifacts, not in place of them

Current behaviour had no home in these skills, so it settled into ADRs — which is why learning a system's state meant reading every decision ever recorded.

1. `openspec/specs/` becomes a third document layer and owns current behaviour, so `docs/adr/` holds decisions only and can freeze once accepted.
2. Every existing artifact stays. `to-tickets` still cuts one issue per ticket, and `to-spec` still writes to the issue tracker — but the issue links to the Change rather than copying it, so a requirement keeps one home.
3. An earlier attempt replaced those artifacts instead, coupling the layer split to a flow rewrite; it was reverted. The accepted cost of this shape is that a requirement and its work order live in two systems.
4. `to-spec` hard-depends on `openspec/` and stops rather than falling back to its old tracker-only behaviour. A fallback was considered and rejected: a repo that silently keeps working without the spec layer never grows one.
