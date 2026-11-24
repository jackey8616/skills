#!/usr/bin/env bash
# Record every comment the cleanup will remove, before anything is removed.
#
#   bash ledger.sh SCRATCHPAD
#
# Run from the repo root. Checks out the sha in SCRATCHPAD/base as a
# worktree, so every position is the base's whatever the setup has edited
# since, and scans it with the repo's own sgconfig.yml, limited to the
# guard's rules. Writes:
#
#   SCRATCHPAD/suppressions.txt      each ast-grep-ignore line, path:line:text
#   SCRATCHPAD/removed-comments.jsonl one object per comment the rules match
#
# Every ast-grep-ignore in the checkout is broken first, so the comments it
# hides are recorded too; its own row reads ast-grep_ignore. Each step runs
# only if the one before it succeeded, and the worktree is removed either
# way. Prints `ledger exit N` and exits N; anything but 0 is a failure.
set -u

dir="$(cd "$1" && pwd)" || { echo "ledger exit 1"; exit 1; }
repo="$PWD"
tree="$dir/base-tree"
base="$(cat "$dir/base")" || { echo "ledger exit 1"; exit 1; }

rc=0
git worktree add -q --detach "$tree" "$base" || { echo "ledger exit 1"; exit 1; }
(
  cd "$tree" &&
    { git grep -n -G 'ast-grep[-]ignore' > "$dir/suppressions.txt" || [ $? = 1 ]; } &&
    { git grep -lz -G 'ast-grep[-]ignore' > "$dir/suppressed" || [ $? = 1 ]; } &&
    xargs -0 -r perl -pi -e 's/ast-grep-ignore/ast-grep_ignore/g' < "$dir/suppressed" &&
    ast-grep scan -c "$repo/sgconfig.yml" --no-ignore hidden --globs '!.git' \
      --filter '^no-(comments|docstrings)-' --info --json=stream > "$dir/removed-comments.jsonl"
) || rc=$?
git worktree remove --force "$tree" || rc=1
echo "ledger exit $rc"
exit "$rc"
