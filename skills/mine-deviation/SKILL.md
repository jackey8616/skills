---
name: mine-deviation
description: Turn a deviation from a skill's SOP into an issue. Pin what happened with evidence, find why it happened, and route it to the skill's source, the repo the skill ran in, or both, as drafts the user sees before anything is sent. Use when you notice you skipped, reordered, or misread a step of a skill you were following, when a reviewer or the user points out such a step, or when a skill you should have used never loaded.
---

# Mine deviation

You followed a skill and didn't do what it says. This skill turns that into an issue someone can act on: what happened, with evidence; why the skill or the repo let it happen; and where a fix belongs. It fixes nothing. It doesn't edit the skill, write its tests, or open pull requests; fixing is another flow, and the issue is its input.

`$ARGUMENTS`: the deviation, in a line: which skill, which step, what happened instead. Empty → take it from the conversation: the step you skipped, the finding that named it, or the correction the user made, and say which you took. Nothing there → ask. Do nothing else first.

## 0. Redo the step

The task you were on still carries the deviation. Redo the step the skill asked for (run the tests, the baseline, the review round) and report what it shows, before anything here. If it shows the task's result is wrong, say so at the top of your reply: an issue about the skill doesn't undo what the skipped step let through. Fixing the task's code is the task's business, not this skill's.

## 1. Pin the deviation

Four lines, each with evidence from this session:

- **Skill and step**: the skill's name and the section or line of its `SKILL.md` you departed from, quoted.
- **What happened**: the command you ran, the edit you made, or the step you left out. Quote the tool call or output. Evidence you only have from the user's word, say so.
- **How it surfaced**: you noticed, a reviewer's finding (quote it), or the user's correction (quote it).
- **Effect**: what the deviation let through or cost, from section 0, or "none seen".

No step to quote → the skill doesn't cover this situation. That is the deviation; say so.

## 2. Find why

Name exactly one cause:

| Cause | Sign |
| ----- | ---- |
| Never loaded | the skill fit the task and never ran |
| Ambiguous step | the step reads two ways, and the run took one |
| Skippable step | nothing stops a run going on without it |
| Conflicting steps | two instructions can't both hold here |
| Step too costly | the step was understood and skipped to save effort |
| Not covered | the skill says nothing about this situation |
| Repo mismatch | the step assumes something this repo doesn't have or do (another test command, layout, or convention) |

## 3. Route it

Where a fix belongs decides where the issue goes. Ask two questions:

- **Would this happen in another repo too?** Then the skill's SOP is where it belongs: an issue for the **skill's source**.
- **Could this repo catch it with its own tools, whatever skill or harness ran?** A CI job, a lint rule, a pre-commit hook, branch protection: a check there holds even when no skill loads. Or is it a repo mismatch, true only here? Then the **repo** is where it belongs: an issue for the repo the skill ran in.

Both can hold. A run that said done without running the tests is a gap in the skill, and also a repo whose CI doesn't run its tests. Then write one issue for each, each linking the other.

A repo mismatch goes to the repo alone when the skill is right in general and this repo is the odd one out: don't bend a skill's SOP to one repo's quirk. But when the skill hard-codes what repos do differently (a command, a path, a layout), the skill assumed too much: the next repo that differs hits the same wall, so the skill gets an issue too.

Say which route you took and why, in a line, in each issue.

## 4. Find the trackers

- **The skill's source**: an installed skill has a manifest in its parent directory (`.jackey8616-skills` for this repo's skills) naming `owner/repo @ ref`. A skill read from a checkout of its source → that checkout's `git remote get-url origin`. Neither → the skill has no source you can name. Say so, and if the route is the skill alone, stop after the reply with the four lines and the cause.
- **The repo**: `git remote get-url origin` in the repo the skill ran in. No remote, or one that isn't on GitHub → no tracker you can reach; draft only.
- **Recurrence**: search each reachable tracker's open issues for the same deviation (`gh issue list -R <owner>/<repo> --search "<skill name> <step words>"`). Found → this is a recurrence: draft a comment on that issue, not a new one. It says the earlier fix, if any, didn't hold. Couldn't search (no `gh`, not logged in, no network) → the draft says "recurrence: not checked", never "none".

## 5. Write the drafts

One file per issue, in your scratchpad, never in a repo. If the tracker's repo has an issue template (`.github/ISSUE_TEMPLATE/`, `.github/ISSUE_TEMPLATE.md`, or `docs/ISSUE_TEMPLATE.md`), follow it: its headings, its fields, its labels. When you can only see the template in a checkout of that repo, read it there. Without one:

```markdown
<skill>: <short name of the deviation>

- Step: <quoted>
- What happened: <one line>
- How it surfaced: <one line>
- Effect: <one line>
- Cause: <one cause from section 2>
- Route: <skill, repo, or both, and why>
- Where a fix could go: <the step, a check the repo could run, a missing step; a direction, not a patch>
- To reproduce: <the situation, the prompt, and what the run did instead>
- Environment: <harness and version>; skill <name> @ <source ref>
- Recurrence: <link to the earlier issue> | not checked | none found
- Related: <link to the other route's issue, once it exists>
```

**Private detail.** The skill's source is read by everyone who uses the skill: its issue holds nothing from this repo. No code, paths, hostnames, project or company names, or transcript beyond the skill's own step; describe the situation in general terms. The repo's issue goes to the repo's own maintainers, so its paths and commands may stay. If the repo is public, nothing private goes in it either.

## 6. Show, then send

Show the user each draft in full, and ask whether to send it. Nothing leaves this session without their yes.

- **Yes** → for the route that has no issue yet, `gh issue create -R <owner>/<repo> --title "<title>" --body-file <draft>`. Two routes → send one first, then put its link under **Related** in the other before sending it, and edit the first to link back (`gh issue edit <n> -R <owner>/<repo> --body-file <updated draft>`). A recurrence → `gh issue comment <n> -R <owner>/<repo> --body-file <draft>`.
- **No**, or it can't be sent → leave the drafts where they are and say where.

Never edit the skill, its installed copies, or the repo's code or config here. A fix written now skips the review the issue is for.

## 7. Reply

```
## Deviation — <skill>, <short name>
Outcome: filed | commented | drafted | reported

<what section 0 showed, if the task's result is wrong>

- Step: <quoted>
- What happened: <one line>
- Cause: <cause>
- Route: <skill | repo | both> — <why>
- Recurrence: <issue | not checked | none found>
- Issues: <link or draft path, per route>
```

- **filed** — an issue was opened for every route.
- **commented** — a recurrence: a comment went on the earlier issue.
- **drafted** — drafts sit in the scratchpad; nothing was sent.
- **reported** — no tracker to draft for; this reply is the whole report.
