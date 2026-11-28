#!/usr/bin/env bash
# Offline tests for scripts/stop-gate.sh, with a fake reviewer
# (REVIEW_GATE_REVIEWER). Each call feeds the gate a Stop hook's JSON, as
# Claude Code would at the end of a turn.
set -uo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
gate="$here/scripts/stop-gate.sh"
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "ok   $1"; }
bad() { fail=$((fail+1)); echo "FAIL $1"; [ -n "${2:-}" ] && printf '     %s\n' "$2"; }
check() { if eval "$2"; then ok "$1"; else bad "$1" "${3:-}"; fi; }
# Dead, or a zombie its new parent hasn't reaped yet.
gone() { case "$(ps -o stat= -p "$1" 2>/dev/null)" in ""|Z*) true ;; *) false ;; esac; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo"; mkdir -p "$repo"; cd "$repo"
git init -q; git config user.email t@t; git config user.name t
echo one > a.txt; git add a.txt; git commit -qm init
st="$(git rev-parse --absolute-git-dir)/review-gate/S1"
unset REVIEW_GATE_INSIDE REVIEW_GATE_REVIEWER

armblock="Done.

\`\`\`review-gate
source: make it two
base: HEAD
requirement:
Make a.txt say two.
Keep it one line.
\`\`\`"

hook() {  # hook [last_message] [session]
  jq -n --arg m "${1:-}" --arg s "${2:-S1}" \
    '{session_id:$s, hook_event_name:"Stop", stop_hook_active:false, last_assistant_message:$m}' \
    | "$gate"
}
report() { printf 'cat >/dev/null; printf "## Verdict\\n%s — reason\\n\\n## Findings\\n1. **[error]** a.txt:1 — FINDING\\n"' "$1"; }
reason() { jq -r .reason <<<"$out"; }
state() { cat "$st/state" 2>/dev/null; }
reset() { rm -rf "$repo/.git/review-gate"; git -C "$repo" checkout -q a.txt; }

# --- Not armed
out="$(REVIEW_GATE_REVIEWER='exit 99' hook "What does this repo do?")"
check "no block, nothing changed: allows, writes no state" '[ -z "$out" ] && [ ! -e "$st" ]'

echo two > a.txt
out="$(REVIEW_GATE_REVIEWER='exit 99' hook "I changed a.txt.")"
check "no block, files changed: reminds once" 'reason | grep -q "isn.t armed" && [ "$(state)" = done ]'
out="$(REVIEW_GATE_REVIEWER='exit 99' hook "Still no block.")"
check "after the reminder: allows" '[ -z "$out" ]'
reset

# --- Arming
echo two > a.txt
out="$(REVIEW_GATE_REVIEWER='exit 99' hook "$(printf '```review-gate\nsource: x\nbase: nope\nrequirement:\nr\n```')")"
check "block with a bad base: says so, doesn't arm" 'reason | grep -q "base nope isn.t a commit" && [ ! -e "$st" ]'
out="$(REVIEW_GATE_REVIEWER='exit 99' hook "$(printf '```review-gate\nsource: x\nbase: HEAD\nrequirement:\n```')")"
check "block with no requirement: says so" 'reason | grep -q "requirement: is empty"'

out="$(REVIEW_GATE_INSIDE=1 REVIEW_GATE_REVIEWER='exit 99' hook "$armblock")"
check "inside the reviewer: allows" '[ -z "$out" ] && [ ! -e "$st" ]'

out="$(REVIEW_GATE_REVIEWER="$(report 'Does not meet requirement')" hook "$armblock")"
check "block arms the gate and reviews at once" '[ "$(jq -r .decision <<<"$out")" = block ] && [ "$(state)" = armed ] && [ "$(cat "$st/round")" = 1 ]'
check "state: base resolved, source, multi-line requirement" \
  '[ "$(cat "$st/base")" = "$(git rev-parse HEAD)" ] && [ "$(cat "$st/source")" = "make it two" ] && [ "$(cat "$st/requirement.md")" = "Make a.txt say two.
Keep it one line." ]'
check "round 1 prompt: skill on line 1, requirement, changed file" \
  'head -1 "$st/prompt-1.md" | grep -qx "/test-first-code-review make it two" && grep -q "Keep it one line." "$st/prompt-1.md" && grep -q "a.txt" "$st/prompt-1.md"'
check "fail verdict: reason carries the report and the protocol" 'reason | grep -q FINDING && reason | grep -q "### Disputed"'

out="$(REVIEW_GATE_REVIEWER='exit 99' hook "Fine." S2)"
check "another session has its own state: S1 untouched, S2 only reminded" \
  'reason | grep -q "isn.t armed" && [ "$(cat "$st/round")" = 1 ] && [ "$(state)" = armed ]'

out="$(REVIEW_GATE_REVIEWER="$(report 'Meets requirement, fixes required')" hook "### Disputed
- FINDING: wrong because XYZZY")"
check "round 2 prompt carries the implementer's reply" 'grep -q XYZZY "$st/prompt-2.md"'
check "fixes-required verdict: blocks, stays armed" '[ "$(jq -r .decision <<<"$out")" = block ] && [ "$(state)" = armed ]'

out="$(REVIEW_GATE_REVIEWER="$(report 'Meets requirement')" hook "Fixed it.")"
check "pass verdict: one last block, then off" '[ "$(jq -r .decision <<<"$out")" = block ] && [ "$(state)" = done ]'
check "rounds log" '[ "$(wc -l < "$st/rounds.tsv")" = 3 ] && grep -q "^3	custom	Meets requirement — reason" "$st/rounds.tsv"'
out="$(REVIEW_GATE_REVIEWER='exit 99' hook "Summary.")"
check "after pass: allows, no reminder" '[ -z "$out" ]'

out="$(REVIEW_GATE_REVIEWER="$(report 'Does not meet requirement')" hook "$armblock")"
check "a new block re-arms from round 1" '[ "$(state)" = armed ] && [ "$(cat "$st/round")" = 1 ]'
out="$(REVIEW_GATE_REVIEWER='exit 99' hook "I dispute everything.
review-gate: off")"
check "review-gate: off turns it off without reviewing" '[ -z "$out" ] && [ "$(state)" = done ]'
reset

# --- Terminal outcomes
echo two > a.txt
out="$(REVIEW_GATE_REVIEWER='exit 99' hook "$(printf '```review-gate\nsource: s\nbase: HEAD\nrequirement:\nr\n```')" >/dev/null; cd "$repo"; git checkout -q a.txt; REVIEW_GATE_REVIEWER='exit 99' hook "Reverted.")"
check "armed, no changes vs base: allows without reviewing" '[ -z "$out" ]'
reset

terminal() {  # terminal <name> <reviewer command> <grep for reason>
  reset; echo two > a.txt
  out="$(REVIEW_GATE_REVIEWER="$2" hook "$armblock")"; want="$3"
  check "$1" '[ "$(state)" = done ] && reason | grep -q "$want"'
}
terminal "cannot determine: off, asks for the install command" "$(report 'Cannot determine')" "command that would install"
terminal "reviewer touched the tree: off, says so" 'cat >/dev/null; echo hacked >> a.txt; printf "## Verdict\nMeets requirement\n"' "changed the working tree"
terminal "reviewer failed: off, names exit status" 'cat >/dev/null; echo oops >&2; exit 3' "exit 3"
terminal "no verdict: off" 'cat >/dev/null; echo no verdict here' "no verdict"
start=$(date +%s)
REVIEW_GATE_TIMEOUT=2 terminal "reviewer timeout: killed by the gate, off" 'cat >/dev/null; sleep 30' "failed"
check "  ...within the timeout" '[ $(( $(date +%s) - start )) -lt 10 ]'

reset; echo two > a.txt
out="$(REVIEW_GATE_REVIEWER='cat >/dev/null; printf "• ## Verdict\n• Does not meet requirement — x\n"' hook "$armblock")"
check "verdict with a UI prefix still parses" 'reason | grep -q "): Does not meet requirement"'

reset; echo two > a.txt
REVIEW_GATE_MAX_ROUNDS=1 REVIEW_GATE_REVIEWER="$(report 'Does not meet requirement')" hook "$armblock" >/dev/null
out="$(REVIEW_GATE_MAX_ROUNDS=1 REVIEW_GATE_REVIEWER='exit 99' hook "Fixed.")"
check "round limit: last block, off, no review" '[ "$(state)" = done ] && reason | grep -q "after 1 rounds"'

reset; echo two > a.txt
jq -n --arg m "$armblock" '{session_id:"S1", last_assistant_message:$m}' \
  | REVIEW_GATE_REVIEWER="cat >/dev/null; echo \$\$ > $tmp/rpid; sleep 30" "$gate" > "$tmp/out" &
gpid=$!; for _ in $(seq 50); do [ -s "$tmp/rpid" ] && break; sleep 0.1; done
kill -TERM "$gpid"; wait "$gpid"; sleep 0.5
check "SIGTERM (Esc): reviewer killed, gate off, no block" \
  'gone "$(cat "$tmp/rpid")" && [ "$(state)" = done ] && [ ! -s "$tmp/out" ]'

echo; echo "$pass passed, $fail failed"; [ "$fail" -eq 0 ]
