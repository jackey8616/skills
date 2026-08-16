---
"mattpocock-skills": minor
---

Give the engineering flow a current-state layer, and freeze ADRs behind it.

Knowing what a system does meant reading every ADR ever written, because current behaviour had nowhere else to live. Three document layers now have one owner each: `openspec/specs/` holds behaviour, `docs/adr/` holds decisions, `CONTEXT.md` holds language. The spec layer absorbs the churn, so ADRs no longer have to — and an accepted one is frozen except for its frontmatter.

OpenSpec is added **alongside** the existing artifacts, not in place of them. `to-spec` still writes to the issue tracker and `to-tickets` still cuts one issue per ticket; the issue points at the change rather than copying it.

- `domain-modeling` gains `DOC-LAYERS.md`, the routing rule for which document a piece of writing belongs in.
- `ADR-FORMAT.md` introduces **decision points** — numbered, never-reused units capped at 1-3 sentences each — so a later ADR can supersede one part of an older one via `superseded: [{point, by}]` without retiring the whole document. `status` still retires it whole.
- `grill-with-docs` stops being a one-line delegation: it checks both its skills loaded, carries the routing rule itself, and closes by scaffolding the change and writing `proposal.md` plus the trade-offs half of `design.md`. Because the proposal is a file, the end of a grilling is now a clean place to `/clear`.
- `to-spec` starts from that proposal, writes the delta specs, and hard-stops without `openspec/` rather than falling back.
- `to-tickets` writes `tasks.md` as the source of truth and cuts issues from it, with references written back.
- `implement` builds only the requirements its ticket covers and hands the merge off.
- **New skill: `change-review`** — the gate before archiving, and the only thing that updates `openspec/specs/`. It reconciles `tasks.md` against the tracker, reviews the change on Coverage and Fidelity as parallel sub-agents, then archives. `implement` finishes at a commit, so nothing is running when the last pull request lands; this fills that gap.
- `setup-matt-pocock-skills` detects `openspec/`, offers to initialize it, and offers a one-time pass that writes an existing repo's current behaviour into `openspec/specs/` — without it, the layer starts empty and stays empty for months.
