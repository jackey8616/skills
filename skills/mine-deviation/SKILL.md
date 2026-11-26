---
name: mine-deviation
description: File an issue against a skill when you didn't follow it, so its maintainer can fix the skill. Use when you realize, mid-task or afterwards, that you skipped, reordered, or misread a step of a skill you were following, or that a skill you should have used never loaded. Also use when the user corrects you for it ("you didn't run the tests", "the skill says to ask first"). Handle the correction, then file it.
---

# Mine deviation

You were following a skill and didn't do what it says: you noticed, or the user corrected you. Tell the skill's maintainer, in an issue, so the next run doesn't do the same. That's the whole job: don't fix the skill here, and don't fix the task here. The task is the business of whatever you were doing; the skill's fix is the maintainer's, with the issue as its input.

`$ARGUMENTS`: the deviation, in a line: which skill, which step, what you did instead. Empty → take it from what you just did, or from the user's correction, and say which deviation you took. Nothing there → ask. Do nothing else first.

## 1. Pin it

Three lines, from this session:

- **Step**: the skill, and the step of its `SKILL.md` you departed from, quoted.
- **What you did**: the command, the edit, or the step you left out. Quote the tool call or its output. If the user caught it, quote their correction too; if you only have their word for it, say so.
- **Why, as far as you can tell**: one line. The step read two ways, nothing stopped you skipping it, it clashed with another step, it cost more than it seemed worth, the skill didn't cover the case, or you simply missed it.

No step to quote → the skill doesn't cover what happened; that is the issue.

## 2. Find the skill's source

An installed skill has a manifest in its parent directory (`.jackey8616-skills` for this repo's skills) naming `owner/repo @ ref`. A skill read from a checkout of its source → that checkout's `git remote get-url origin`.

Neither → there is nowhere to file. Put the three lines in your reply, say the skill has no source you can name, and stop. Write no draft: one with nowhere to go sits in a scratchpad and is forgotten.

## 3. Check it isn't filed already

Search the source's open issues: `gh issue list -R <owner>/<repo> --search "<skill name> <words from the step>"`. Found → this is a repeat: your draft is a comment on that issue, saying it happened again. Can't search (no `gh`, not logged in, no network) → the draft says "not checked", never "none found".

## 4. Draft it

Write the draft to your scratchpad, never into a repo. If the source has an issue template (`.github/ISSUE_TEMPLATE/`, `.github/ISSUE_TEMPLATE.md`, or `docs/ISSUE_TEMPLATE.md`), follow it: its headings, fields, and labels. Without one:

```markdown
<skill>: <short name of the deviation>

- Step: <quoted>
- What happened: <one line>
- Why: <one line>
- To reproduce: <the situation and the request, and what the run did instead>
- Environment: <harness and version>; skill <name> @ <source ref>
- Already filed: <link to the earlier issue> | not checked | none found
```

Everyone who uses the skill reads its tracker, so the draft holds nothing from the user's project: no code, paths, hostnames, project or company names, and no transcript beyond the skill's own step. Describe the situation in general terms.

## 5. Ask, then file

Paste the draft in full in your reply, not just its path, and ask whether to send it. Nothing leaves this session without the user's yes.

- **Yes** → `gh issue create -R <owner>/<repo> --title "<title>" --body-file <draft>`, or for a repeat `gh issue comment <n> -R <owner>/<repo> --body-file <draft>`.
- **No**, or it can't be sent → leave the draft where it is and say where.

## Reply

```
## Deviation — <skill>, <short name>
Outcome: filed | commented | drafted | reported

- Step: <quoted>
- What happened: <one line>
- Why: <one line>
- Already filed: <issue | not checked | none found>
- Issue: <link | draft path | none: no source>
```

- **filed** — an issue was opened.
- **commented** — a repeat: a comment went on the earlier issue.
- **drafted** — the draft sits in the scratchpad; nothing was sent.
- **reported** — no source to file against; this reply is the whole report.
