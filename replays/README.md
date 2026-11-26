# Replays

Task files and results for `/skills-replay`, for every repo it replays. Not a skill: it sits outside `skills/`, so `install.sh` never copies it, and a replay's `skills` arm, which loads the installed skills, never sees a PR's hidden tests or rubric.

```
replays/
  <repo>/
    <repo>-pr<N>/task.yaml        one merged PR to replay
    results/<YYYY-MM-DD>-<model>.md   one replay of that repo's PRs on one model
```

`skills/skills-replay/references/task-file.md` describes a task file. Each replay runs against a clone of the PR's repo, passed as `--repo`.

Everything here is public, with the repo: the user's original prompts, the PRs' commits and test names, and each rubric. Replay only public repos from here.
