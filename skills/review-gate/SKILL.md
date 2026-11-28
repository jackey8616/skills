---
name: review-gate
description: Gate the end of your turn on an independent test-first review, so Claude Code keeps fixing until a second model passes the work. Codex reviews when installed, otherwise a fresh Claude. Use when the user asks for a review-and-fix loop, a second model's review before they push, a cross-vendor review, or "don't stop until it passes review", even if they don't name the gate. For one review with no fixing, use test-first-code-review.
hooks:
  Stop:
    - hooks:
        - type: command
          # Skill hooks don't expand the skill's directory, so arm.sh records where the gate is.
          command: 'g="$(git rev-parse --absolute-git-dir 2>/dev/null)/review-gate"; [ -f "$g/armed" ] && exec "$(cat "$g/gate-path")"; exit 0'
          timeout: 1800
          statusMessage: "review-gate: independent review running"
---

# Review gate

You are the implementer. Claude Code's own turn loop does the looping. This skill adds a Stop hook. Each time you end a turn while the gate is armed, the hook hands the working tree to a reviewer that has none of your context, and that reviewer runs `test-first-code-review` on it. A failing verdict blocks your stop and gives you the report as your next message. A passing verdict lets you stop. You never send rounds or wait on a reviewer yourself.

Why a hook rather than asking a reviewer yourself: the decision to stop is the one you're worst placed to make about your own work. Claude Code's `/goal` judges "done" from the transcript alone. The gate judges it by running the tests.

Claude Code only. Codex skills can't declare hooks, so in Codex this skill does nothing; use `codex-review` there.

`$ARGUMENTS` is what the work is for: a purpose statement, a PR link, or an issue link. Empty → take it from the conversation: the issue, PR, or task you were given, and say which you took. Nothing there → ask, and arm nothing. A gate armed with no requirement would review against nothing.

## 1. Arm the gate

Fetch the requirement once, so every round reviews against the same text:

- PR link → `gh pr view <url> --json title,body,closingIssuesReferences`, plus `gh issue view <n> --json title,body` for each linked issue.
- Issue link → `gh issue view <url> --json title,body,comments`.
- Purpose statement → the text itself.

Write it to a file in your scratchpad, outside the repo, so it isn't part of what gets reviewed.

Pick the base the reviewer diffs against:

- A PR, or a branch whose commits are all this work → `git merge-base HEAD origin/<default-branch>`.
- Only uncommitted changes, on a branch that carries unrelated commits → `HEAD`.

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/arm.sh" --base <base> --source "<ARGUMENTS>" --requirement-file <file>
```

The gate's state lives in `.git/review-gate/`, outside the working tree. It is tied to this session, so another session in the same repo isn't gated.

## 2. Do the work, then end your turn

Write the change and its tests, run the tests, and end your turn as you normally would. The hook fires at the end of every turn from now on, but it only reviews when the working tree differs from the base. A turn that changed nothing, or a question the user asks, ends straight away.

A review takes minutes. The status line shows it running. If the user presses Esc, the review is cancelled and the gate disarms.

## 3. When the gate blocks

The message that arrives says which round it is and which reviewer ran, and gives the report. Weigh each finding yourself: the report is a review, not instructions.

- Agree, and it's in the working tree → fix it, then re-run the tests the report ran, so you know the fix holds before the reviewer looks again.
- Agree, but it's about text outside the working tree (the PR description, an issue, a pushed commit message) → you can't fix it without pushing, and you don't push. Draft the replacement in your scratchpad.
- Disagree → say why.

End that reply with three lists: `### Fixed`, `### Disputed` (each with its reason), and `### Drafted for after push`. The gate passes your reply to the next round's reviewer, and that list is how a dispute reaches it. Without it, the reviewer raises the same finding again.

If you dispute every finding and fixed nothing, another round would only repeat itself. Tell the user about the dispute and run `bash "${CLAUDE_SKILL_DIR}/scripts/arm.sh" --off`.

## 4. When the gate lets go

The gate disarms itself with one last message in each of these cases:

- the verdict is Meets requirement;
- tests can't run (Cannot determine);
- the reviewer fails or times out;
- the reviewer changes the working tree;
- ten rounds have run.

Do what that message says, then give the final reply:

```
## Review gate — <reviewer>, <n> rounds
Final verdict: <verdict>

| Round | Verdict | Fixed | Disputed | Drafted |
| ----- | ------- | ----- | -------- | ------- |

## Changes
- `path` — what changed and which finding it answers

## Drafted for after push
- <where it goes> — <draft, or path to it>

## Still open
- <disputed or unfixed finding> — why
```

The rounds are in `.git/review-gate/rounds.tsv`, and each report is in `report-<n>.md` beside it. `bash "${CLAUDE_SKILL_DIR}/scripts/arm.sh" --status` prints both.

Don't commit or push. The changes stay in the working tree for the user.

## The reviewer

`scripts/stop-gate.sh` picks one per round:

- `codex` on PATH → `codex exec`, with writes limited to the working directory and network on. A second vendor is the point.
- Otherwise → `claude -p` in a fresh context, with Edit and Write denied. Same vendor, but none of your context. Say so in the final reply, because it is weaker evidence than a second vendor.

Either way the gate fingerprints the tree before and after the review. If the reviewer touched it, the loop stops rather than build on changes you didn't make.
