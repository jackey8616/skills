#!/usr/bin/env bash
# Offline checks for the behaviour evals in tests/evals/. The evals are billed
# model runs (see CLAUDE.md); this runs no model. It checks every case is in
# the shape `claude plugin eval` loads (skills-audit's check-evals.py), and
# that each case's prompt and fixture are what the case says: no arguments
# for the empty-arguments case; for the other two, PR #12 as a merge whose
# second parent brings test_minutes.py, which fails on the first parent and
# passes on the second, with no prompt left anywhere in the repo for the
# case that must ask for it, and a task file that passes the dry check for
# the case that must count. Both name ../skills/replays as the replays
# directory, which the scaffold makes beside the project, outside it.
#
#   bash skills/skills-replay/tests/evals.test.sh
set -uo pipefail

TESTS="$(cd "$(dirname "$0")" && pwd)"
EVALS="$TESTS/evals"
REPLAY="$TESTS/../scripts/replay.py"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0
ok()   { pass=$((pass + 1)); echo "  ok   $1"; }
bad()  { fail=$((fail + 1)); echo "  FAIL $1 — got: $2"; }
check() { if eval "$2"; then ok "$1"; else bad "$1" "$3"; fi; }

echo "format"
while IFS='|' read -r verdict name why; do
  if [ "$verdict" = ok ]; then ok "$name"; else bad "$name" "$why"; fi
done < <(python3 "$TESTS/../../skills-audit/scripts/check-evals.py" "$(dirname "$TESTS")")

prompt_of() {
  python3 -c 'import re,sys; print(re.match(r"---\n.*?\n---\n(.*)", open(sys.argv[1]).read(), re.S).group(1).strip())' \
    "$EVALS/$1/prompt.md"
}

# build <case> — run its scaffold in a fresh project dir, as a run would; prints the dir.
build() {
  local p="$WORK/$1/r/x/project"
  mkdir -p "$p" && (cd "$p" && bash "$EVALS/$1/place-files.sh") >/dev/null 2>&1 && echo "$p"
}

# test_at <dir> <merge> <rev> — whether the merge's test_minutes.py passes at <rev>.
test_at() {
  local t="$WORK/t-$RANDOM"
  git -C "$1" worktree add -q --detach "$t" "$3" &&
    git -C "$1" show "$2^2:test_minutes.py" > "$t/test_minutes.py"
  (cd "$t" && python3 -m unittest -q test_minutes >/dev/null 2>&1)
  local r=$?
  git -C "$1" worktree remove --force "$t"
  return $r
}

pr_premises() {
  local c="$1" p="$2"
  local merge
  merge=$(git -C "$p" log --merges --format=%H -1)
  check "$c: PR #12 is a merge" '[ -n "$merge" ] && git -C "$p" log -1 --format=%s "$merge" | grep -q "pull request #12"' "$(git -C "$p" log --oneline)"
  local fork
  fork=$(git -C "$p" merge-base "$merge^1" "$merge^2")
  check "$c: main moved on after the branch left it" '[ "$fork" != "$(git -C "$p" rev-parse "$merge^1")" ] && [ "$(git -C "$p" log -1 --format=%s "$fork")" = "Parse durations" ]' "$(git -C "$p" log --oneline --graph)"
  check "$c: the PR's diff is duration.py and test_minutes.py" '[ "$(git -C "$p" diff --name-only "$fork" "$merge^2" | sort | tr "\n" " ")" = "duration.py test_minutes.py " ]' "$(git -C "$p" diff --name-only "$fork" "$merge^2")"
  check "$c: the test fails on the base" '! test_at "$p" "$merge" "$fork"' "passes"
  check "$c: the test passes on the head" 'test_at "$p" "$merge" "$merge^2"' "fails"
  check "$c: no remote to ask" '[ -z "$(git -C "$p" remote)" ]' "$(git -C "$p" remote)"
  check "$c: the tree is clean" '[ -z "$(git -C "$p" status --porcelain)" ]' "$(git -C "$p" status --porcelain)"
}

echo "cases"
for case_dir in "$EVALS"/*/; do
  c="$(basename "$case_dir")"
  case "$c" in results | benchmarks | mocks) continue ;; esac
  prompt="$(prompt_of "$c")"
  case "$c" in
    empty-arguments-asks)
      check "$c: /skills-replay with no arguments" '[ "$prompt" = /skills-replay ]' "$prompt" ;;
    asks-for-original-prompt)
      check "$c: PR 12, one model, a replays dir" '[ "$prompt" = "/skills-replay . 12 --model claude-haiku-4-5 --replays ../skills/replays" ]' "$prompt"
      p="$(build "$c")" || { bad "$c: fixture builds" "scaffold failed"; continue; }
      pr_premises "$c" "$p"
      check "$c: an empty replays dir beside the project" '[ -d "$p/../skills/replays" ] && [ -z "$(ls -A "$p/../skills/replays")" ]' "$(ls -A "$p/../skills/replays" 2>&1)"
      check "$c: nothing replay-like in the project" '[ ! -e "$p/replays" ] && [ ! -e "$p/.skills-replay" ]' "$(ls -A "$p")"
      check "$c: no Claude-Session trailer or prompt in history" '! git -C "$p" log --format=%B | grep -qiE "claude-session|prompt"' "$(git -C "$p" log --format=%B)" ;;
    counts-before-running)
      check "$c: PR 12, one model, 2 runs, a replays dir" '[ "$prompt" = "/skills-replay . 12 --model claude-haiku-4-5 --runs 2 --replays ../skills/replays" ]' "$prompt"
      p="$(build "$c")" || { bad "$c: fixture builds" "scaffold failed"; continue; }
      pr_premises "$c" "$p"
      task="$p/../skills/replays/project/project-pr12/task.yaml"
      check "$c: the task file is in the replays dir, named for the project" '[ -f "$task" ]' "$(ls -R "$p/../skills" 2>&1)"
      check "$c: the task's base is where the branch left main" 'grep -q "^base: $(git -C "$p" merge-base HEAD^1 HEAD^2)$" "$task"' "$(grep ^base "$task")"
      check "$c: the task names no skill" '! grep -q "^skills:" "$task"' "$(cat "$task")"
      check "$c: the prompt calls no slash command" 'python3 -c "import sys,yaml; t=yaml.safe_load(open(sys.argv[1])); sys.exit(t[\"prompt\"].lstrip().startswith(\"/\") or \"plain_prompt\" in t)" "$task"' "$(grep -A1 prompt "$task")"
      if python3 "$REPLAY" run "$task" "$WORK/$c/dry" --repo "$p" --model none --runs 0 >/dev/null 2>&1; then
        s="$(python3 "$REPLAY" summarize "$WORK/$c/dry/project-pr12/"*)"
        check "$c: the dry check passes the original PR" 'echo "$s" | grep -qF "| original PR | 1/1 | 1/1 |"' "$s"
        check "$c: the dry check raises no warning" '! echo "$s" | grep -q "^- "' "$s"
      else
        bad "$c: the dry check runs" "replay.py run --runs 0 failed"
      fi ;;
    *)
      bad "$c: has a premise check here" "add one for this case" ;;
  esac
done

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
