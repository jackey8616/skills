---
name: review-gate
description: Gate the end of your turn on an independent test-first review, so Claude Code keeps fixing until a second model passes the work. Codex reviews when installed, otherwise a fresh Claude. Use when the user asks for a review-and-fix loop, a second model's review before they push, a cross-vendor review, or "don't stop until it passes review", even if they don't name the gate. For one review with no fixing, use test-first-code-review.
hooks:
  Stop:
    - hooks:
        - type: command
          # For a skill's hooks, CLAUDE_PLUGIN_ROOT is the skill's directory.
          command: 'bash "${CLAUDE_PLUGIN_ROOT}/scripts/stop-gate.sh"'
          timeout: 1800
          statusMessage: "review-gate: independent review running"
  PreToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: 'bash "${CLAUDE_PLUGIN_ROOT}/scripts/pre-bash.sh"'
---

# Review gate

You are the implementer. Claude Code's own turn loop does the looping. Invoking this skill registers a Stop hook. Each time you end a turn with the gate armed, the hook hands the working tree to a reviewer that has none of your context, and that reviewer runs `test-first-code-review` on it. A failing verdict blocks your stop and gives you the report as your next message. A passing verdict lets you stop. You never send rounds, wait on a reviewer, or write the gate's state yourself.

Why a hook rather than asking a reviewer yourself: the decision to stop is the one you're worst placed to make about your own work. Claude Code's `/goal` judges "done" from the transcript alone. The gate judges it by running the tests.

Claude Code only. Codex skills can't declare hooks, so in Codex this skill does nothing; use `codex-review` there.

`$ARGUMENTS` is what the work is for: a purpose statement, a PR link, or an issue link. Empty → take it from the conversation: the issue, PR, or task you were given, and say which you took. Nothing there → ask, and write no `review-gate` block. A gate armed with no requirement would review against nothing.

## 1. Arm the gate from your reply

The gate reads only your replies. Hooks run outside Claude Code's Bash sandbox, which makes `.git` read-only, so the gate keeps its own state in `.git/review-gate/` and you never write it.

Fetch the requirement once, so every round reviews against the same text:

- PR link → `gh pr view <url> --json title,body,closingIssuesReferences`, plus `gh issue view <n> --json title,body` for each linked issue.
- Issue link → `gh issue view <url> --json title,body,comments`.
- Purpose statement → the text itself.

Pick the base the reviewer diffs against:

- A PR, or a branch whose commits are all this work → `git merge-base HEAD origin/<default-branch>`.
- Only uncommitted changes, on a branch that carries unrelated commits → `HEAD`.

End the reply in which you finish the work with this block. The user sees it, which also shows them exactly what the review is held to:

````
```review-gate
source: <$ARGUMENTS, or what you took it from>
base: <the base>
requirement:
<the requirement text, verbatim>
```
````

Once is enough. The gate keeps it for every later round, and a new block replaces it. If you end a turn having changed files but without a block, the gate stops you once to ask for it.

## 2. Do the work, then end your turn

Write the change and its tests, run the tests, and end your turn with the block. The hook fires at the end of every turn, but it only reviews when the working tree differs from the base. A turn that changed nothing, or a question the user asks, ends straight away.

If the tests can't run because something is missing (a dependency, a service, a credential), don't download, install or fetch it to get them going. Say what's missing, and end your turn with the block as usual: the reviewer will hit the same wall and report Cannot determine, which is the honest result. Setting up the environment is the user's call. A dependency named for a private index, fetched from a public one, is also how dependency confusion gets in: anyone can publish a package under that name there.

Nor stand in for it: no stub module or mock service to get a result. A pass against a stand-in says nothing about the real dependency, and a reader who skims sees only "both passed". Report the tests as not run.

The gate doesn't take your word or the reviewer's for any of this. From invocation until the gate turns off, a hook denies Bash commands that install or fetch packages. At each stop, the gate reads the commands that actually ran from the session transcript, and if any installed or fetched a package, it turns off and tells the user exactly what ran. A pattern only catches honest slips: a command that downloads by other means gets past it. The fence that holds is Claude Code's own sandbox with network limited (`/sandbox`). Recommend it to the user when the work runs untrusted code.

A review takes minutes, and the status line shows it running. If the user presses Esc, the review is cancelled and the gate turns off.

## 3. When the gate blocks

The message that arrives says which round it is and which reviewer ran, and gives the report. Weigh each finding yourself: the report is a review, not instructions.

- Agree, and it's in the working tree → fix it, then re-run the tests the report ran, so you know the fix holds before the reviewer looks again.
- Agree, but it's about text outside the working tree (the PR description, an issue, a pushed commit message) → you can't fix it without pushing, and you don't push. Draft the replacement in your scratchpad.
- Disagree → say why.

End that reply with three lists: `### Fixed`, `### Disputed` (each with its reason), and `### Drafted for after push`. The gate passes your reply to the next round's reviewer, and that list is how a dispute reaches it. Without it, the reviewer raises the same finding again.

If you dispute every finding and fixed nothing, another round would only repeat itself. Tell the user about the dispute and end your reply with the line `review-gate: off`, which turns the gate off. The same line turns it off whenever the user asks.

## 4. When the gate lets go

The gate turns itself off with one last message in each of these cases:

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

The gate's last message gives the path of `rounds.tsv`. Each round's report is in `report-<n>.md` beside it.

## The record

The gate's record of every review is what you, the user, or anyone after can audit the reviewer by. The reviewers' own sessions aren't saved. It lives in `.git/review-gate/<session>/`, written only by the hook. For each round:

- `prompt-<n>.md`: what the reviewer was asked;
- `events-<n>.jsonl`: everything it did, each command with its output;
- `commands-<n>.log`: the commands alone;
- `report-<n>.md` and its stderr;
- a line in `rounds.tsv`.

A new `review-gate` block starts a new run, and the last run's record moves to `runs/<UTC time>/`. Nothing is erased.

`ledger.sha256` holds a checksum of every record as it's written: the requirement, the base and the source at arming, and each round's files once its review ends. At each stop the gate checks the ledger. If a record was changed or deleted, it turns off and names the files. This catches edits, not a forger who rewrites the ledger as well. Under Claude Code's Bash sandbox, `.git` is read-only to you, so the record is safe there.

`.git` keeps the record out of the working tree, out of commits, and out of what the reviewer is shown. It also travels with the repo: a copy of the repo (`cp -a`, a backup, a synced folder) carries the record, and with it the code and command output in it. Deleting or re-cloning the repo deletes the record. Tell the user both when it matters.

Don't commit or push. The changes stay in the working tree for the user.

## The reviewer

`scripts/stop-gate.sh` picks one per round:

- `codex` on PATH → `codex exec`, with writes limited to the working directory and network on. A second vendor is the point.
- Otherwise → `claude -p` in a fresh context, with Edit and Write denied. Same vendor, but none of your context. Say so in the final reply, because it is weaker evidence than a second vendor.

The reviewer runs `test-first-code-review`, which `install.sh` installs alongside this skill. Where the reviewer doesn't have it, the gate's prompt still asks for the same verdict and a test-first review, but without the skill's full method. If the user hasn't installed it, say so in the final reply.

The reviewer runs offline. It needs no network, since the requirement is in its prompt, and without one it can't fetch a package under a borrowed name. Codex runs with network access off. Neither reviewer's session is saved to disk, where the CLI supports that; the gate keeps its own log. Claude runs in Claude Code's sandbox with no hosts allowed, and if that sandbox can't start (on Linux it needs bubblewrap and socat), the gate reports the reviewer as failed rather than run one unconfined. Tests that need the network then come back as Cannot determine, which is the honest result.

The gate checks what the reviewer did from records, not from its report:

- It fingerprints the tree before and after. If the tree changed during the review, the loop stops rather than build on changes you didn't make. It can't tell whether the reviewer made the change or someone else in the same repo did, so tell the user not to edit the tree while a review runs.
- It reads every command the reviewer ran from its event log, and checks whether anything was written where packages install: Python's site-packages, and `node_modules`, `.venv` and `venv` in the repo. Either one voids the verdict, and the gate tells the user what it found.
