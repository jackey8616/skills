---
name: test-first-code-review
description: Review a fix by running its tests first, then reading the code. Takes a purpose, PR, or issue. Never touches the codebase.
disable-model-invocation: true
---

# Test-first code review

You are the reviewer of `$ARGUMENTS`: a purpose statement, a PR link, or an issue link. The implementation under review is a fix, and a fix must come with test cases.

Tests come first. Run them before you read the implementation, so the outcome of the run — not your reading of the code — sets what the review looks at. Then report every error, misleading, or incorrect content you find.

`$ARGUMENTS` empty → ask what to review. Do nothing else first.

## Read-only

Read-only means you never touch anything in the codebase. Running tests is the one thing you execute in it.

- No edits, creates, or deletes in the repo — tracked or untracked. That includes `.git`: no commits, branch switches, stashes, resets, fetches, or worktrees.
- No dependency installs, no test flags that write back (snapshot updates, `--fix`, auto-formatters).
- No PR or issue comments, reviews, labels, or status changes. Findings go in your reply, nowhere else.
- Take `git status --porcelain` before the first run and after the last. Anything the tests left behind is a finding — say what appeared. Don't clean it up.
- Outside the repo, in a temp dir, you may write throwaway tests and negative controls to probe the fix. Never copy them into the repo.

## 1. Pin the requirement

The requirement is what the fix must achieve. Get it from the source, not from the code.

If the prompt already gives you the requirement text or the change's file list, use it as given. Don't fetch it again.

- **Issue link** → `gh issue view <url> --comments`. Requirement is the reported problem and any acceptance criteria. Find the fix: a linked PR, or ask.
- **PR link** → `gh pr view <url> --comments`. Requirement comes from the linked issue if there is one, else the PR description.
- **Purpose statement** → that text is the requirement. The implementation is the current branch's diff against its merge-base with the default branch, plus uncommitted changes.

Write the requirement down as a short list of checkable claims. Every later judgement is against this list.

## 2. Run the tests

You MUST run the fix's test cases, and you run them now — before reading the implementation.

- Find them from the change's file list (from the prompt, `gh pr view <url> --json files`, or `git diff --name-only <merge-base>`): the test files it adds or changes. Read test names, not the code under test.
- **No tests in the fix → stop.** Verdict is "Does not meet requirement", with one **error** finding: the fix has no tests. Don't run other tests, don't review the code — without tests there is nothing to measure it against. Go to section 4.
- Use the project's own runner and commands (package scripts, Makefile, CI config). Run the specific tests first, then the suite they live in.
- Tests exist but can't run (missing dependency, no access) → stop. Verdict is "Cannot determine"; name what's missing and the command the user would run.
- Record each command, revision, exit status, and pass/fail counts. Quote failure output verbatim — trimmed, not paraphrased.
- When feasible, run the new tests against the base revision too. A test that passes without the fix doesn't prove the fix. Extract the base outside the repo with `git archive <base-rev> | tar -x -C <tmp-dir>` — it reads local `.git` only, no network. Only when the revision you need isn't in the local repo (an unfetched PR head), clone into a temp dir instead: `gh repo clone <repo> <tmp-dir>`. Delete temp dirs when done.

## 3. Review the code

Now read the diff — the implementation and the tests — with the run results in hand.

- Every failure: trace it to its cause in the diff.
- Every pass: check the test actually exercises a requirement claim. A green test that asserts nothing, or never reaches the fixed path, proves nothing. A throwaway negative control (section Read-only) is the way to show it.
- Each requirement claim gets one status:
  - **met** — a passing test exercises it.
  - **not met** — a test, yours or theirs, shows it failing.
  - **not covered** — it could be tested here, but no test does. That is an **error** finding.
  - **untestable** — it can't be exercised in this environment at all (a live third-party service, real hardware). Give the reason. This doesn't count against the fix.

Then hunt for:

- **Error** — wrong behaviour, a failing or flaky test, an unhandled case the requirement implies, a test that asserts nothing meaningful, a claim not covered.
- **Misleading** — names, comments, test titles, commit messages, or PR text that claim something the code doesn't do. A test titled for a case it never reaches.
- **Incorrect** — factual mistakes in docs, comments, or the PR description: wrong APIs, wrong numbers, wrong explanations of the root cause.

Every finding needs evidence: a `file:line`, a quoted test output, or a quoted line of the requirement. A failing throwaway test counts — quote its output. No evidence, no finding.

## 4. Verdict

Pick exactly one:

- **Meets requirement** — tests ran, every claim is met or untestable, and no **error** findings.
- **Does not meet requirement** — the fix has no tests, or any claim is not met or not covered, or any **error** finding stands.
- **Cannot determine** — tests exist but couldn't run. Never use it for untestable claims or missing tests.

Misleading and incorrect findings don't change the verdict on their own. Report them anyway.

## 5. Reply

```
## Verdict
Meets requirement | Does not meet requirement | Cannot determine — one-line reason

## Test runs
| Command | Revision | Result |
| ------- | -------- | ------ |

## Requirement
- [met | not met | not covered | untestable] <claim> — <which test shows it, or why untestable>

## Findings
1. **[error|misleading|incorrect]** `path:line` — what is wrong, and the evidence.
```

Most severe finding first. Nothing found → say so in one line under Findings. Stopped early for no tests → Test runs and Requirement say "not run". Don't pad with style nits or praise.
