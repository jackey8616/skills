# The task file

One PR, one file: `<repo>/.skills-replay/<task-id>/task.yaml`, in the repo the PR was merged into. `replay.py` strips `.skills-replay/` from every snapshot, so a run never sees it, even when a later PR's base already holds it.

```yaml
id: acme-api-pr42            # <repo>-pr<N>; also the results' directory name
pr: 42
merged_at: 2026-08-14        # for reading results against a model's training cutoff
base: 3f1c2e9...             # full sha: the base branch just before the PR
head: 9ab04d1...             # full sha: the PR's last commit, the reference
prompt: |                    # what the user typed, exactly, slash command and all
  /test-first-code-review the retry fix on this branch
plain_prompt: |              # the same request for an agent without the skill
  Review the retry fix on this branch: run its tests first, then read the code.
skills:                      # what the `skill` arm loads
  - name: test-first-code-review
    repo: ~/src/skills       # a local clone of the skills repo
    ref: 1a2b3c4             # the skills repo's commit the PR was made with
setup:                       # run in each snapshot before the model starts
  - npm ci
hidden_tests:                # test files the PR added or changed
  - test/retry.test.ts
test_command: npx vitest run test/retry.test.ts
checks:                      # anything else CI would hold the change to
  - name: types
    run: npx tsc --noEmit
  - name: lint
    run: npm run lint
rubric:                      # 3–6 statements a good change makes true
  - Retries stop after the configured limit instead of looping
  - A failed retry surfaces the last error, not the first
max_turns: 80
timeout_seconds: 1800
leak_patterns: []            # extra regexes that would mean a run saw the PR
```

## Filling it in

**base and head.** For a merged PR:

```bash
gh pr view 42 --json number,mergedAt,headRefOid,mergeCommit,files,title,body
git fetch origin pull/42/head                   # squash-merged heads aren't on any branch
git merge-base <headRefOid> <mergeCommit>^1     # → base
```

`head` is `headRefOid`. `base` is where the PR's branch met the base branch, not `baseRefOid`, which can be a later commit the PR never saw. Check that `git diff <base> <head>` is the PR's diff and nothing else.

**prompt.** The words the user typed, not the PR title. Look in this order, and say which you used:

1. The PR's commits: a `Claude-Session:` trailer names the session. If a session tool can read its events (`list_events` with `kinds: ["user"]`), the first user message is the prompt.
2. The PR body, if it quotes the request.
3. Ask the user. Don't write one yourself: a prompt you wrote measures your wording, not the user's task.

A session that took several user turns can't be replayed from its first message alone: the later turns steered it. Ask the user whether to fold them into one prompt or to drop this PR.

**plain_prompt.** Needed when `prompt` starts with a slash command: the plain arm has no such command, and the CLI would answer "unknown skill" and stop. Keep the request and its arguments, and say in plain words what the user wanted done, not how the skill does it. "Review the retry fix" is the user's task; "run its tests first, then read the code" is the skill's method. Leave the method out unless the user's own words held it, so the plain arm isn't handed the skill in disguise. Show the user both prompts before running.

**skills.** The skill the PR was made with, at the commit of the skills repo that was installed then. An install copies `main`, so take `git -C <skills> log -1 --format=%h --before=<the PR's first commit date> main`, unless the user knows better.

**hidden_tests and test_command.** The test files in `gh pr view --json files` that the PR added or changed. `test_command` runs them and nothing slow. `replay.py` overlays them from `head` after each run, so a run is graded on the PR's own tests whether it wrote tests or not. They should fail on the base and pass on `head`: `base-check.json` and the reference row of the report show both. A PR with no tests can still be replayed. Set `test_command` to the suite the repo already has, and lean on `rubric`.

**setup.** What makes the tests runnable in a fresh copy: installing dependencies, building. Not the CI's deploy steps. It runs before the model starts and its result is committed, so the model's diff holds only the model's work.

**rubric.** From the PR's description and its review comments: what the change had to get right. Each statement is checkable from the diff and the reply, and holds for the original PR. The report grades the reference against it too, and a statement the PR itself fails is a bad statement. Don't describe the PR's code ("adds a `maxRetries` field"): another correct change would fail that.

## What a run can't see

- **Git history.** Each snapshot is one commit, with no remote.
- **GitHub.** `gh`, `git fetch/pull/clone/remote`, WebFetch and WebSearch are denied, no MCP server starts, and `GH_TOKEN`/`GITHUB_TOKEN` are unset. A run can still reach the network through other tools, for example `curl` in Bash. `meta.json` lists `leaks`: tool calls and results that name the PR's head commit, its page, `gh pr`, `gh api` or `git fetch`. Leave a run with leaks out of the comparison, and say so in the report.
- **The user's skills.** `CLAUDE_CONFIG_DIR` is a new empty directory with only the arm's skills. Claude Code's built-in skills still load in both arms. They're the same on both sides, so they don't change the comparison.

What it can't hide: a model trained after `merged_at` on a public repo may have seen the PR. Note it next to that model's results. A replay is most telling on PRs merged after the model's training cutoff.

On a machine where Claude Code signs in through the keychain or `~/.claude`, an empty `CLAUDE_CONFIG_DIR` has no sign-in. `replay.py doctor --live` finds out. The fix is `ANTHROPIC_API_KEY`, or `CLAUDE_CODE_OAUTH_TOKEN` from `claude setup-token`, in the environment.
