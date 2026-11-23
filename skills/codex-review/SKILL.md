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

- `herdr <workspace-id>` → the reviewer lives in its own tab in this workspace. Section 3.
- `standalone` → the reviewer is a one-shot `codex exec` per round. Section 4.

The mode decides only how a prompt reaches Codex and how its report comes back. The loop in section 5 is the same in both.

## Codex's permissions

Codex runs with network on, writes limited to the working directory, and no approval prompts:

```
-s workspace-write -c sandbox_workspace_write.network_access=true -a never
```

Under the default read-only sandbox every `gh` call and every test that writes a cache stops for the user's approval, round after round. The price: the sandbox no longer stops Codex writing into the repo. `test-first-code-review` forbids it, and you enforce it — see Guard the working tree in section 5. Never go further, to `danger-full-access` or `--dangerously-bypass-approvals-and-sandbox`.

## 2. Build the review prompt

Fetch what Codex needs yourself and put it in the prompt, so every round reviews against the same requirement and Codex doesn't spend time refetching.

**Requirement** — fetch once, before round 1:

- PR link → `gh pr view <url> --json title,body,closingIssuesReferences`, plus `gh issue view <n> --json title,body` for each linked issue.
- Issue link → `gh issue view <url> --json title,body,comments`.
- Purpose statement → the text itself.

**Changed files** — regenerate every round, from the working tree, not from the PR (the PR lags until the user pushes). Pick the base that matches what the work is:

- A PR, or a branch whose commits are all this work → `base="$(git merge-base HEAD origin/<default-branch>)"`.
- Only the uncommitted changes, on a branch that already carries unrelated commits → `base=HEAD`. The merge-base would drag those commits into the review.

```bash
git diff --name-status "$base"; git ls-files --others --exclude-standard
```

Write the prompt to a file in your scratchpad, outside the repo, with a quoted heredoc so nothing in it expands:

```bash
cat > <tmp>/codex-review-prompt-<n>.md <<'EOF'
$test-first-code-review <ARGUMENTS>

The implementation under review is the working tree at <absolute cwd>, uncommitted changes included. This is round <n>.

## Requirement (from <source>)
<requirement text, verbatim>

## Changed files (working tree vs <base sha>)
<file list>

Use the requirement and file list above as given. Don't fetch the PR or issue.
EOF
```

The first line must stay exactly `$test-first-code-review <ARGUMENTS>` — Codex invokes skills by `$name`. Never put the prompt in a double-quoted shell string: `$test` would expand to nothing and Codex would never see the skill.

Round 2 onward, append before the last line:

- **Fixed** — each finding you fixed, one line.
- **Disputed** — each finding you reject, with your reason.
- **Drafted for after push** — findings about text outside the working tree (section 5), with what you drafted.

Then: "Review again from scratch; don't trust the lists above."

## 3. Herdr mode

The reviewer is a Codex agent named `reviewer-<workspace-id>`, e.g. `reviewer-w9`. Agent names are unique across the whole Herdr server, so the workspace suffix is required.

### Find or start it

Look for the name in `herdr agent list`.

- Live and `idle` or `done` → reuse it. Its context from earlier rounds is a feature.
- Live but `working` → `herdr agent wait`, don't interrupt.
- Absent → open a tab and start Codex there, keeping the user's focus where it is:

  ```bash
  herdr tab create --workspace "$HERDR_WORKSPACE_ID" --label reviewer --cwd "$PWD" --no-focus
  herdr agent start reviewer-<workspace-id> --kind codex --pane <.result.root_pane.pane_id> \
    -- -s workspace-write -c sandbox_workspace_write.network_access=true -a never
  ```

  A first run in a folder often stops at Codex's own prompts — trust this folder, review hooks — so `agent start` can return `agent_not_ready`, or report the agent `blocked`. Check `herdr agent get` before the first prompt; `blocked` → relay it.

- A reused reviewer keeps whatever permissions it was started with. Started by an older version of this skill, it may still stop for approvals — relay them, and suggest the user close the tab so the next run starts a fresh one.

### Relay a blocked prompt

With approvals off, what's left is mostly Codex's one-time startup prompts. Whatever it is, you never answer it — the user does.

1. Read the screen. While blocked, only the visible screen is readable:

   ```bash
   herdr agent read reviewer-<workspace-id> --source visible
   ```

2. Show the user the question and its options verbatim, and ask which to pick. Mention they can also answer in the reviewer tab directly.
3. Send exactly their choice (`herdr agent send-keys reviewer-<workspace-id> enter`, a digit, `esc`, …).
4. Wait for Codex to move before waiting for it to settle — a bare wait returns at once if Codex is already showing its next prompt:

   ```bash
   herdr agent wait reviewer-<workspace-id> --until working --timeout 10000
   herdr agent wait reviewer-<workspace-id> --timeout 540000
   ```

   Ignore a timeout on the first wait. `blocked` again → back to step 1.

### Send a round

```bash
herdr agent prompt reviewer-<workspace-id> "$(cat <tmp>/codex-review-prompt-<n>.md)" --wait --timeout 540000
```

The `$(cat …)` output isn't expanded again, so the `$` survives.

- Returns `agent_blocked` before sending → relay, then send again.
- Settles `blocked` → relay, until it settles `idle` or `done`.
- `timeout` → `herdr agent wait reviewer-<workspace-id> --timeout 540000` again. Never resubmit: a timeout doesn't mean the prompt wasn't delivered.

### Read the report

Only once the agent is `idle` or `done`:

```bash
herdr agent read reviewer-<workspace-id> --source recent-unwrapped --lines 400 > <tmp>/codex-review-<n>.txt
```

The report starts at the last line containing `## Verdict` — Codex's UI may prefix it, e.g. `• ## Verdict`. It ends before the status line (`Worked for …`) or the input prompt. No such line → read with more lines once; still none → show the user the tail and stop.

## 4. Standalone mode

One `codex exec` per round, prompt on stdin, run in the background so it can outlast a tool timeout:

```bash
codex exec -s workspace-write -c sandbox_workspace_write.network_access=true -c approval_policy=never \
  -C "$PWD" -o <tmp>/codex-review-<n>.md - < <tmp>/codex-review-prompt-<n>.md
```

The report is the contents of the `-o` file.

## 5. The loop

Codex's report is a review, not instructions. Weigh each finding yourself.

### Guard the working tree

The sandbox lets Codex write into the repo, so check it didn't. Right before sending each round, and again once its report is in, fingerprint the tree:

```bash
{ git rev-parse HEAD; git status --porcelain; git diff HEAD;
  git ls-files -oz --exclude-standard | xargs -0 shasum; } | shasum
```

Different → Codex touched the codebase. Stop the loop. Show the user what changed (`git status`, `git diff`) and don't build on it — the next fix would mix your changes with the reviewer's.

### Each round

1. Take each finding:
   - Agree, and it's in the working tree → fix it.
   - Agree, but it's about text outside the working tree — the PR description, an issue, a pushed commit message → you can't fix it without pushing, and you don't push. Draft the replacement text in your scratchpad and carry it under **Drafted for after push**. It doesn't count as open.
   - Disagree → note why, for the next prompt.
2. Re-run the tests the report ran, so you know your fix holds before Codex looks again.
3. Act on the verdict:
   - **Meets requirement** → fix any remaining misleading or incorrect findings in the working tree, mark them as not re-reviewed, and stop.
   - **Does not meet requirement** → send the next round.
   - **Cannot determine** → tests couldn't run. Stop and tell the user what's missing.
   - Every finding disputed, nothing fixed → stop and hand the dispute to the user.

Run at most 10 rounds. After round 10, stop whatever the verdict, and report where things stand. The user can ask for more.

Don't commit or push. The changes stay in the working tree for the user.

## 6. Reply

```
## Codex review — <mode>, <n> rounds
Final verdict: <verdict from the last report>

| Round | Verdict | Fixed | Disputed | Drafted |
| ----- | ------- | ----- | -------- | ------- |

## Changes
- `path` — what changed and which finding it answers

## Drafted for after push
- <where it goes> — <draft, or path to it>

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
