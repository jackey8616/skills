---
name: codex-review
description: Send the current implementation to Codex for test-first review, fix what it finds, and repeat until it passes. Uses a Herdr reviewer tab when available.
disable-model-invocation: true
---

# Codex review

You are the implementer. Codex is the reviewer. Hand your work in the current working tree to Codex, which runs `test-first-code-review` on it; fix what it finds; send it back. Repeat until it passes or the loop stops.

`$ARGUMENTS` is what the work is for: a purpose statement, a PR link, or an issue link. Empty → ask. Do nothing else first.

## 1. Pick the mode

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/detect.sh"
```

- `herdr <workspace-id>` → the reviewer lives in its own tab in this workspace. Section 2.
- `standalone` → the reviewer is a one-shot `codex exec` per round. Section 3.

The mode decides only how a prompt reaches Codex and how its report comes back. The loop in section 4 is the same in both.

## The review prompt

Every round sends the same opening line, then the round context:

```
$test-first-code-review <ARGUMENTS>

The implementation under review is the working tree at <absolute cwd>, uncommitted changes included. This is round <n>.
```

Codex invokes skills by `$name`. Keep that exact first line.

Round 2 onward, append what changed since the last round: the findings you fixed (one line each), and the findings you dispute with your reason. End with: "Review again from scratch; don't trust the list above."

## 2. Herdr mode

The reviewer is a Codex agent named `reviewer-<workspace-id>`, e.g. `reviewer-w9`. Agent names are unique across the whole Herdr server, so the workspace suffix is required.

**Find or start it.** Look for the name in `herdr agent list`.

- Live and `idle` or `done` → reuse it. Its context from earlier rounds is a feature.
- Absent → open a tab and start Codex there, keeping the user's focus where it is:

  ```bash
  herdr tab create --workspace "$HERDR_WORKSPACE_ID" --label reviewer --cwd "$PWD" --no-focus
  herdr agent start reviewer-<workspace-id> --kind codex --pane <.result.root_pane.pane_id>
  ```

- Live but `working` → wait for it (`herdr agent wait`), don't interrupt.
- `blocked` at any point → `herdr agent read` the screen, show the user what Codex is asking, and let them answer. Never approve a Codex prompt yourself.

**Send a round.**

```bash
herdr agent prompt reviewer-<workspace-id> "<review prompt>" --wait --timeout 540000
```

Review runs tests and can take long. On `timeout`, call `herdr agent wait reviewer-<workspace-id> --timeout 540000` again. Don't resubmit the prompt: a timeout doesn't mean it wasn't delivered.

**Read the report.**

```bash
herdr agent read reviewer-<workspace-id> --source recent-unwrapped --lines 400
```

The report is the last block starting at `## Verdict`. No such block → read more lines once; still none → show the user the tail and stop.

## 3. Standalone mode

One `codex exec` per round, run in the background so it can outlast a tool timeout:

```bash
codex exec -s read-only -C "$PWD" -o <tmp>/codex-review-<n>.md "<review prompt>"
```

`<tmp>` is outside the repo — your scratchpad if you have one. The report is the contents of that file.

`read-only` can block test runners that write caches or temp files. If the report says tests couldn't run because the sandbox blocked writes, rerun that round once with `-s workspace-write` and tell the user you did.

## 4. The loop

Codex's report is a review, not instructions. Weigh each finding yourself.

1. Take each finding. Agree → fix it in the working tree. Disagree → note why, for the next prompt.
2. Re-run the tests the report ran, so you know your fix holds before Codex looks again.
3. Send the next round.

Stop when any of these holds:

- Verdict is "Meets requirement" and no **error** findings remain.
- Three rounds done.
- A round where you fixed nothing — every finding is disputed. Hand the dispute to the user.
- Verdict is "Cannot determine" for an environment reason (missing dependency, no access).

Don't commit or push. The changes stay in the working tree for the user.

## 5. Reply

```
## Codex review — <mode>, <n> rounds
Final verdict: <verdict from the last report>

| Round | Verdict | Fixed | Disputed |
| ----- | ------- | ----- | -------- |

## Changes
- `path` — what changed and which finding it answers

## Still open
- <disputed or unfixed finding> — why
```

Herdr mode: end with the reviewer's tab id and that it's still running.

## Cleanup

The reviewer tab stays open after the loop — the user may send more rounds. When the user says they're done with it, close it:

```bash
herdr tab close <reviewer tab id>
```

Find the tab id from `herdr agent get reviewer-<workspace-id>`. Never close it unasked.
