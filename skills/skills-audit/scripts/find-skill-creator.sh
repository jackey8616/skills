#!/usr/bin/env bash
# Print the directory of an installed skill-creator: one holding the grader
# instructions, the benchmark script, and the viewer this skill reuses.
# $SKILL_CREATOR wins if set. Otherwise it searches beside this skill, then
# ~/.claude/skills, ~/.claude/plugins, ~/.agents/skills, and /mnt/skills, or
# the directories in $SKILL_CREATOR_SEARCH (colon-separated) instead.
# Exits 1, printing nothing, if none is found.
#
#   bash find-skill-creator.sh
set -uo pipefail

usable() {
  [ -f "$1/agents/grader.md" ] && [ -f "$1/scripts/aggregate_benchmark.py" ] &&
    [ -f "$1/eval-viewer/generate_review.py" ]
}

if [ -n "${SKILL_CREATOR:-}" ]; then
  usable "$SKILL_CREATOR" && { (cd "$SKILL_CREATOR" && pwd); exit 0; }
  exit 1
fi

here="$(cd "$(dirname "$0")/.." && pwd)"
IFS=: read -r -a roots <<< "${SKILL_CREATOR_SEARCH:-$here/..:$HOME/.claude/skills:$HOME/.claude/plugins:$HOME/.agents/skills:/mnt/skills}"
for root in "${roots[@]}"; do
  [ -d "$root" ] || continue
  while IFS= read -r grader; do
    dir="$(dirname "$(dirname "$grader")")"
    usable "$dir" && { (cd "$dir" && pwd); exit 0; }
  done < <(find -L "$root" -maxdepth 6 -path '*/skill-creator/agents/grader.md' 2>/dev/null | sort)
done
exit 1
