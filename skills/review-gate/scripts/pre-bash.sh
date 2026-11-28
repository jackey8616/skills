#!/usr/bin/env bash
# Claude Code PreToolUse hook for Bash: from the moment the skill is invoked
# until the gate turns off, deny commands that install or fetch packages.
# A pattern catches honest slips, not determined ones (python -c, curl): the
# Stop hook also reads what actually ran from the transcript, and the real
# fence is Claude Code's own sandbox with network limited.
set -uo pipefail
. "$(dirname "$0")/lib.sh"

[ -n "${REVIEW_GATE_INSIDE:-}" ] && exit 0
in="$(cat)"
gd="$(git rev-parse --absolute-git-dir 2>/dev/null)" || exit 0
sid="$(jq -j '.session_id // "none"' <<<"$in" | tr -c 'A-Za-z0-9_-' _)"
[ "$(cat "$gd/review-gate/$sid/state" 2>/dev/null)" = done ] && exit 0

hit="$(jq -r '.tool_input.command // ""' <<<"$in" | install_lines | head -3)"
[ -n "$hit" ] || exit 0
jq -n --arg h "$hit" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny",
  permissionDecisionReason: ("review-gate: blocked a command that installs or fetches a package: " + $h + "\nDon'\''t set up the environment to make tests run; say what is missing and let the review report Cannot determine.")}}'
