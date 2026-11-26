---
name: skill-deviation-eliminator
description: Turn a deviation from a skill's SOP into a change to that skill, backed by an eval case that reproduces it, and land it as a pull request or an issue for the skill's maintainer. Use when you notice you skipped, reordered, or misread a step of a skill you were following, when a reviewer or the user points out such a step, or when a skill you should have used never loaded.
---

# Skill deviation eliminator

You followed a skill and didn't do what it says. This skill finds out why the skill let that happen, changes the skill so the next run doesn't, and proves the change with a case that reproduces the deviation. The fix lands in the skill's source as a change for its maintainer to review. Nothing here changes the code the skill was working on, and nothing here judges that code's quality: a bug in the output is the task's business, not this skill's.

`$ARGUMENTS`: the deviation, in a line: which skill, which step, what happened instead. Empty → take it from the conversation: the step you skipped, the finding that named it, or the correction the user made, and say which you took. Nothing there → ask. Do nothing else first.

## 0. Repair the task first

The task you were on still carries the deviation. Redo the step the skill asked for (run the baseline, the tests, the review round) before anything here, and say what it changed. Landing a fix to the skill doesn't undo what the skipped step let through.

## 1. Pin the deviation

Write it down as four lines, each with evidence from this session:

- **Skill and step**: the skill's name and the section or line of its `SKILL.md` you departed from, quoted.
- **What happened**: the command you ran, the edit you made, or the step you left out. Quote the tool call or output.
- **How it surfaced**: you noticed, a reviewer's finding (quote it), or the user's correction (quote it).
- **Effect**: what the deviation let through or cost, or "none seen".

No quote of the step → this isn't a deviation from the skill. It may be a gap the skill never covered; say so, and treat the missing step as the deviation's cause in section 2.

## 2. Find the source and its history

- **The source**: the repo the skill was installed from. An installed skill has a manifest in its parent directory (`.jackey8616-skills` for this repo's skills) naming `owner/repo @ ref`. Working inside a checkout of that repo → that checkout.
- **Not from a source you can name** (a built-in skill, a plugin's, one written by hand) → report the deviation to the user with the four lines above, say there is no source to land it in, and stop.
- **History**: read `skills/<name>/tests/deviations.md` in the source, and its open issues (`gh issue list -R <owner>/<repo> --search "<skill name> in:title"`). The same deviation already recorded → this is a recurrence. Add to that entry or issue; don't open another. A recurrence means the earlier fix didn't hold, and section 3 must pick a stronger fix than the one it used.

## 3. Diagnose the cause

Name exactly one. The cause decides where the fix goes:

| Cause | Sign | Fix |
| ----- | ---- | --- |
| Never loaded | the skill fit the task and never ran | its `description`: the trigger the run missed |
| Ambiguous step | the step reads two ways, and you took one | the step's wording, with the reason it's there |
| Skippable step | nothing stops the run going on without it | a script that checks the step's precondition and refuses to go on, like `checks.sh` in `setup-annotation-guard` |
| Conflicting steps | two instructions can't both hold here | which wins, and why |
| Step too costly | the step was understood and skipped to save effort | move the work into a script, so doing it costs one command |
| Not covered | the skill says nothing about this situation | a step for it, or a stop that hands it to the user |

Fixes get stronger down this list of kinds: wording, then a stop, then a script. A recurrence moves at least one kind stronger than the earlier fix. The fix must hold in every harness the skill ships for (`agents/openai.yaml` means Codex too), so it can't lean on one harness's hooks or settings.

Write the fix for the class of deviation, not this one run. A skill runs thousands of times; wording that only fits today's situation makes it worse. Never fix it by deleting the step or weakening a check the skill makes.

## 4. Reproduce it as a case

Write an eval case in `skills/<name>/tests/evals/<case>/`, in the format the source's other cases use. In this repo, read `skills/skills-audit/references/writing-cases.md` and follow it. The case sets up the situation the deviation happened in, and its assertions check the step was done. The skill as it was must fail it: that failure is the evidence that the case sees the deviation.

Build the fixture from scratch. Never copy the user's code, paths, hostnames, or transcript into it: the case ships to everyone who reads the source.

Then run the case's offline check (`tests/evals.test.sh`) and, if the `claude` CLI is here, the case itself on the old skill and the new one. That's two billed runs: say so first.

```bash
claude plugin eval <old-skill-copy> --eval-dir tests/evals --scaffold --allow-tools Bash Write Edit --runs 1
claude plugin eval skills/<name> --eval-dir tests/evals --scaffold --allow-tools Bash Write Edit --runs 1
```

Run them on a copy of the skill whose `tests/evals/` holds only the new case, so the rest of its cases don't bill too. The full comparison across every case is `/skills-audit <name>`, for the maintainer.

Can't reproduce it (it hung on context this session had and a fixture can't hold) → no case. The change goes out **unverified**, with each reproduction you tried and why it didn't reproduce.

## 5. Record it

Add an entry to `skills/<name>/tests/deviations.md` in the source (create it if missing):

```markdown
## <YYYY-MM-DD> — <short name of the deviation>
- Step: <section of SKILL.md, quoted>
- What happened: <one line, no private detail>
- Cause: <one cause from section 3>
- Fix: <what changed, and its kind: wording, stop, or script>
- Evidence: case `<case>` (old: fail, new: pass) | unverified: <why>
- Recurrence of: <earlier entry> | none
```

## 6. Land it

Check whether you can push to the source:

```bash
gh api repos/<owner>/<repo> --jq .permissions.push
```

- **`true`** → a branch off the default branch, one commit with the skill change, the case, and the entry, and a pull request. Its body: the four lines from section 1, the cause, the fix, and the evidence. Run the source's lint and the skill's offline tests before pushing (in this repo, `python3 lint-skills.py` and `bash skills/<name>/tests/evals.test.sh`). Don't merge it: the maintainer reviews every change to a skill.
- **Anything else** (no push access, no `gh`, no network) → draft an issue instead. Write it to your scratchpad: the four lines from section 1 with private detail removed, the cause, the proposed change as a diff, the case, the entry, and the harness and version you ran in with the skill's source ref. Show the user the whole draft, then ask whether to submit it. Yes → `gh issue create -R <owner>/<repo> --title "<skill>: <deviation>" --body-file <draft>`. No, or it can't be sent → leave the draft where it is and say where.

Nothing goes outside this session without the user seeing it first, except a pull request to a source they can push to.

Installed copies of the skill (`~/.claude/skills`, `~/.agents/skills`) are never edited: the next install overwrites them. Until the fix lands and the user reinstalls, the deviation can happen again here, so say so.

## 7. Reply

```
## Skill deviation — <skill>, <short name>
Outcome: eliminated | changed, unverified | reported | drafted

- Step: <quoted>
- What happened: <one line>
- Cause: <cause> → Fix: <kind>: <what changed>
- Evidence: <case and its two results, or why unverified>
- Recurrence: <earlier entry or issue, or none>
- Landed: <PR link | issue link | draft path>
- Task repaired: <what redoing the step changed>
```

Pick the outcome by what was shown, not by what was done:

- **eliminated** — a case reproduces the deviation, the old skill fails it, and the new one passes.
- **changed, unverified** — the skill changed, but no case shows the change works.
- **reported** — an issue was opened; the skill is unchanged.
- **drafted** — a draft sits in the scratchpad; nothing was sent.
