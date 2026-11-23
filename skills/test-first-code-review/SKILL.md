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

Read-only means you never touch anything in the codebase. Running tests is the one thing you execute.

- No edits, creates, or deletes in the repo — tracked or untracked. That includes `.git`: no commits, branch switches, stashes, resets, fetches, or worktrees.
- No dependency installs, no test flags that write back (snapshot updates, `--fix`, auto-formatters).
- No PR or issue comments, reviews, labels, or status changes. Findings go in your reply, nowhere else.
- Take `git status --porcelain` before the first run and after the last. Anything the tests left behind is a finding — say what appeared. Don't clean it up.
- Need code that isn't checked out (the PR head, or the base revision)? Clone into a temp dir outside the repo — `gh repo clone <repo> <tmp-dir>`, then `gh pr checkout <n>` or `git checkout <rev>` there. Delete the temp dir when done.
- Tests can't run without something missing → stop, name what's missing and the command the user would run.

## 1. Pin the requirement

The requirement is what the fix must achieve. Get it from the source, not from the code.

- **Issue link** → `gh issue view <url> --comments`. Requirement is the reported problem and any acceptance criteria. Find the fix: a linked PR, or ask.
- **PR link** → `gh pr view <url> --comments`. Requirement comes from the linked issue if there is one, else the PR description.
- **Purpose statement** → that text is the requirement. The implementation is the current branch's diff against its merge-base with the default branch, plus uncommitted changes.

Write the requirement down as a short list of checkable claims. Every later judgement is against this list.

## 2. Run the tests

You MUST run the fix's test cases, and you run them now — before reading the implementation.

- Find them from the change's file list (`gh pr view <url> --json files`, or `git diff --name-only <merge-base>`): the test files it adds or changes. Read test names, not the code under test.
- No tests in the fix → that is a finding, severity **error**. Run the existing tests nearest the changed files instead, so the report says what passes today.
- Use the project's own runner and commands (package scripts, Makefile, CI config). Run the specific tests first, then the suite they live in.
- Record each command, revision, exit status, and pass/fail counts. Quote failure output verbatim — trimmed, not paraphrased.
- When feasible, run the new tests against the base revision too, in a temp clone. A test that passes without the fix doesn't prove the fix.

## 3. Review the code

Now read the diff — the implementation and the tests — with the run results in hand.

- Every failure: trace it to its cause in the diff.
- Every pass: check the test actually exercises a requirement claim. A green test that asserts nothing, or never reaches the fixed path, proves nothing.
- Each requirement claim: met, not met, or not covered by any test.

Then hunt for:

- **Error** — wrong behaviour, a failing or flaky test, an unhandled case the requirement implies, a test that asserts nothing meaningful.
- **Misleading** — names, comments, test titles, commit messages, or PR text that claim something the code doesn't do. A test titled for a case it never reaches.
- **Incorrect** — factual mistakes in docs, comments, or the PR description: wrong APIs, wrong numbers, wrong explanations of the root cause.

Every finding needs evidence: a `file:line`, a quoted test output, or a quoted line of the requirement. No evidence, no finding.

## 4. Reply

```
## Verdict
Meets requirement | Does not meet requirement | Cannot determine — one-line reason

## Test runs
| Command | Revision | Result |
| ------- | -------- | ------ |

## Requirement
- [met | not met | not covered] <claim> — <which test shows it>

## Findings
1. **[error|misleading|incorrect]** `path:line` — what is wrong, and the evidence.
```

Most severe finding first. Nothing found → say so in one line under Findings. Don't pad with style nits or praise.
