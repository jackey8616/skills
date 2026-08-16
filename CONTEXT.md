# Matt Pocock Skills

A collection of agent skills (slash commands and behaviors) loaded by Claude Code. Skills are organized into buckets and consumed by per-repo configuration emitted by `/setup-matt-pocock-skills`.

## Language

**Issue tracker**:
The tool that hosts a repo's issues — GitHub Issues, Linear, a local `.scratch/` markdown convention, or similar. Skills like `to-tickets`, `to-spec`, and `triage` read from and write to it.
_Avoid_: backlog manager, backlog backend, issue host

**Issue**:
A single tracked unit of work inside an **Issue tracker** — a bug, task, spec, or slice produced by `to-tickets`.
_Avoid_: ticket (use only when quoting external systems that call them tickets, or for a **Decision ticket** — see below)

**Decision ticket**:
A `wayfinder` unit — a child **Issue** of a `wayfinder:map` holding a *question* whose resolution is a decision, not a slice of a build to execute. The **decision** qualifier is what keeps it distinct from an implementation ticket; `wayfinder` introduces the term, then uses "ticket".

**Map**:
The single `wayfinder:map`-labelled **Issue** that charts one effort — its **Destination**, its notes, and an index of the **Decision tickets** already closed. An index over decisions, not a place they live: each one's detail stays in its ticket.
_Avoid_: plan, roadmap

**Destination**:
What reaching the end of a **Map** looks like — the thing the effort is finding its way to, named as the first act of charting. It is what fixes the **Map**'s scope: work lying beyond it is out of scope rather than fog.
_Avoid_: goal, outcome (neither carries the scope-fixing sense); spec, change (both are terms of their own here — see Flagged ambiguities)

**Triage role**:
A canonical state-machine label applied to an **Issue** during triage (e.g. `needs-triage`, `ready-for-afk`). Each role maps to a real label string in the **Issue tracker** via `docs/agents/triage-labels.md`.

**Change**:
A unit of work under `openspec/changes/<id>/` — the folder holding a **Proposal**, its delta specs, its design notes and its task list. It archives when the work lands, merging its deltas into current state.
_Avoid_: change proposal (ambiguous — see Flagged ambiguities)

**Proposal**:
The `proposal.md` file inside a **Change**: the problem, the solution in the user's own words, and what is explicitly out of scope. Written by a `grilling` session as its closing act. It is one file in a **Change**, not the **Change** itself.

**Settled question**:
A node in a `grilling` design tree that the user has answered. The unit of progress in an interview, and the thing that pushes the frontier outward. Most settle into a change's rationale; a few resolve language; very few clear the ADR gate.
_Avoid_: decision (overloaded — see Flagged ambiguities)

**Decision point**:
A numbered, stable unit inside an ADR — the smallest thing a later ADR can supersede. Writing an ADR as decision points is what makes it *addressable*, so supersession can name a part rather than retiring the whole document.
_Avoid_: order friendly (ambiguous — reads as "meant to be read in order"), clause, section

## Relationships

- An **Issue tracker** holds many **Issues**
- An **Issue** carries one **Triage role** at a time
- A **Decision ticket** is an **Issue** (a child of a `wayfinder:map`)
- An ADR holds one or more **Decision points**; supersession targets a **Decision point**, not the ADR
- A **Decision point** is not a **Decision ticket** — one is a part of a written decision, the other is a unit of work that produces one
- A `grilling` session produces many **Settled questions**; only the few clearing the ADR gate become **Decision points** in an ADR
- A **Map** has exactly one **Destination**, and indexes many closed **Decision tickets**
- A **Decision ticket**'s resolution is a **Settled question** that outlives the session that settled it — the same gate applies, so most stay in their ticket and only a few become **Decision points** in an ADR

## Flagged ambiguities

- "backlog" was previously used to mean both the *tool* hosting issues and the *body of work* inside it — resolved: the tool is the **Issue tracker**; "backlog" is no longer used as a domain term.
- "backlog backend" / "backlog manager" — resolved: collapsed into **Issue tracker**.
- "change proposal" meant both the whole `openspec/changes/<id>/` folder and the `proposal.md` file inside it. Resolved: the folder is a **Change**, the file is a **Proposal**. The two have different authors — a `grilling` writes the **Proposal**, `to-spec` writes the delta specs — so conflating them routes requirements into the wrong file.
- "decision" was doing four jobs: a node in a `grilling` design tree, the thing an ADR records, a **Decision ticket**, and a **Decision point**. Resolved: the grilling node is a **Settled question**, and "decision" unqualified now means only what clears the ADR gate. The reasoning that a grilling is a decision tree, *therefore* its purpose is to produce ADRs, is the error this ambiguity produces — most **Settled questions** never become ADRs.
- "order friendly" was used for the property an ADR needs before its parts can be superseded individually — resolved: it means *addressable*, not *readable in sequence*. The unit it addresses is a **Decision point**.
- `wayfinder` described the kinds of **Destination** an effort can have as "a spec, decision, or change" — all three of which are load-bearing terms here (delta specs under `openspec/`, the ADR-gated sense of "decision", and **Change** as the `openspec/changes/<id>/` folder), and none of which it meant in that sense. Resolved: **Destination** is described without reusing those three words.
