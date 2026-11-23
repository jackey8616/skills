---
name: test-first-code-review
description: Read-only review of a fix against its purpose, PR, or issue. Runs the fix's tests and reports errors, misleading content, and incorrect content.
disable-model-invocation: true
---

# Test-first code review

You are the reviewer of `$ARGUMENTS`: a purpose statement, a PR link, or an issue link. The implementation under review is a fix, and a fix must come with test cases. You run those tests, judge whether the outcome meets the requirement, and report every error, misleading, or incorrect content you find.

`$ARGUMENTS` empty → ask what to review. Do nothing else first.

## Read-only

Running tests is the one thing you execute. Everything else is look, don't touch.

- No edits to tracked files. No commits, pushes, branch switches, stashes, or resets in the user's working tree.
- No PR or issue comments, reviews, labels, or status changes. Findings go in your reply, nowhere else.
- No dependency installs. Tests can't run without one → stop and name the missing piece and the command the user would run.
- Need another revision to run (the PR head, or the base for a comparison)? Use a throwaway worktree outside the repo: `git worktree add --detach <tmp-dir> <rev>`. Remove it with `git worktree remove <tmp-dir>` when done.

## 1. Pin the requirement

The requirement is what the fix must achieve. Get it from the source, not from the code.

- **Issue link** → `gh issue view <url> --comments`. Requirement is the reported problem and any acceptance criteria. Find the fix: a linked PR, or ask.
- **PR link** → `gh pr view <url> --comments` and `gh pr diff <url>`. Requirement comes from the linked issue if there is one, else the PR description.
- **Purpose statement** → that text is the requirement. The implementation is the current branch's diff against its merge-base with the default branch, plus uncommitted changes.

Write the requirement down as a short list of checkable claims. Every later judgement is against this list.

## 2. Find the tests

List the test cases the fix adds or changes, by file and test name.

No tests in the fix → that is a finding, severity **error**. Still run the existing tests nearest the changed code, so the report says what does and doesn't pass today.

## 3. Run the tests

You MUST run the given test cases. Reading them is not enough.

- Use the project's own runner and commands (package scripts, Makefile, CI config). Run the specific tests first, then the suite they live in.
- Record each command, exit status, and pass/fail counts. Quote failure output verbatim — trimmed, not paraphrased.
- When feasible, run the new tests against the base revision too, in a worktree. A test that passes without the fix doesn't prove the fix.

## 4. Judge the outcome

For each requirement claim: met, not met, or not covered by any test. A green run only counts toward a claim the tests actually exercise.

Then hunt for:

- **Error** — wrong behaviour, a failing or flaky test, an unhandled case the requirement implies, a test that asserts nothing meaningful.
- **Misleading** — names, comments, test titles, commit messages, or PR text that claim something the code doesn't do. A test titled for a case it never reaches.
- **Incorrect** — factual mistakes in docs, comments, or the PR description: wrong APIs, wrong numbers, wrong explanations of the root cause.

Every finding needs evidence: a `file:line`, a quoted test output, or a quoted line of the requirement. No evidence, no finding.

## 5. Reply

```
## Verdict
Meets requirement | Does not meet requirement | Cannot determine — one-line reason

## Requirement
- [met | not met | not covered] <claim> — <which test shows it>

## Test runs
| Command | Revision | Result |
| ------- | -------- | ------ |

## Findings
1. **[error|misleading|incorrect]** `path:line` — what is wrong, and the evidence.
```

Most severe finding first. Nothing found → say so in one line under Findings. Don't pad with style nits or praise.
