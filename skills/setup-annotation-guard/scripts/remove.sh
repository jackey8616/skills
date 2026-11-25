#!/usr/bin/env bash
# Remove the comments the guard's rules ban, then tidy what that leaves.
#
#   bash remove.sh SCRATCHPAD
#
# Run from the repo root, once every ast-grep-ignore is deleted. Snapshots
# the working tree to SCRATCHPAD/snap (`git stash create`, or HEAD when the
# tree is clean), so the setup's own edits aren't taken for removals.
#
# Each removal is a pair: a --json=stream scan records exactly what the same
# scan with -U then deletes. One rule per pair, every no-comments-* and
# no-docstrings-* rule in rules/ in name order: when several rules fix one
# file (an HTML file's comment, <script>, and <style>), one -U keeps only
# one rule's fixes. Then the empty {} that {/* … */} leaves in JSX, in the
# files the removal changed. Then tidy.py on all the records, in order.
#
# Exits with tidy.py's status (3: lines to fix by hand), or 2 if a step
# fails. ast-grep exiting 1 is expected, since it reports every match as an
# error, and matches without a fix (docstrings) remain after -U; its messages
# are shown only when it fails.
set -u
shopt -s nullglob

dir="$(cd "$1" && pwd)" || exit 2
here="$(cd "$(dirname "$0")" && pwd)"

scan() {
  local err rc
  { err="$(ast-grep scan "$@" 2>&1 1>&3 3>&-)"; rc=$?; } 3>&1
  [ "$rc" -le 1 ] || { printf '%s\n' "$err" >&2; echo "ast-grep scan $* exited $rc" >&2; exit 2; }
}

snap="$(git stash create)" || exit 2
snap="${snap:-$(git rev-parse HEAD)}" || exit 2
echo "$snap" > "$dir/snap" || exit 2
echo "snapshot $snap"

cuts="$dir/cuts"
rm -rf "$cuts" && mkdir "$cuts" || exit 2
n=0
for rule in rules/*.yml; do
  id="$(basename "$rule" .yml)"
  case "$id" in no-comments-*|no-docstrings-*) ;; *) continue ;; esac
  n=$((n + 1)); out="$cuts/$(printf %02d "$n").jsonl"
  : > "$out" || exit 2
  scan --no-ignore hidden --globs '!.git' --filter "^$id\$" --json=stream > "$out"
  scan --no-ignore hidden --globs '!.git' --filter "^$id\$" -U > /dev/null
done

files=()
while IFS= read -r -d '' f; do files+=("$f"); done < <(git diff --name-only -z "$snap")
for lang in Tsx JavaScript; do
  n=$((n + 1)); out="$cuts/$(printf %02d "$n").jsonl"
  : > "$out" || exit 2
  [ "${#files[@]}" -gt 0 ] || continue
  jsx="{id: empty-jsx, language: $lang, rule: {kind: jsx_expression, regex: '^\{\s*\}\$'}, fix: ''}"
  scan --inline-rules "$jsx" --json=stream "${files[@]}" > "$out"
  scan --inline-rules "$jsx" -U "${files[@]}" > /dev/null
done

python3 "$here/tidy.py" --base "$snap" "$cuts"/*.jsonl
