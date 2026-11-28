#!/usr/bin/env bash
# Offline tests for scripts/stop-gate.sh and scripts/arm.sh, with a fake reviewer.
set -uo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
gate="$here/scripts/stop-gate.sh"; arm="$here/scripts/arm.sh"
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "ok   $1"; }
bad() { fail=$((fail+1)); echo "FAIL $1"; [ -n "${2:-}" ] && printf '     %s\n' "$2"; }
# Dead, or a zombie its new parent hasn't reaped yet.
gone() { case "$(ps -o stat= -p "$1" 2>/dev/null)" in ""|Z*) true ;; *) false ;; esac; }
check() { if eval "$2"; then ok "$1"; else bad "$1" "${3:-}"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo"; mkdir -p "$repo"; cd "$repo"
git init -q; git config user.email t@t; git config user.name t
echo one > a.txt; git add a.txt; git commit -qm init
echo "Make a.txt say two." > "$tmp/req.md"
st="$(git rev-parse --absolute-git-dir)/review-gate"
unset CLAUDE_CODE_SESSION_ID REVIEW_GATE_INSIDE

hook() {  # hook [last_message] [session]
  jq -n --arg m "${1:-}" --arg s "${2:-S1}" \
    '{session_id:$s, hook_event_name:"Stop", stop_hook_active:false, last_assistant_message:$m}' \
    | "$gate"
}
report() { printf 'cat >/dev/null; printf "## Verdict\\n%s — reason\\n\\n## Findings\\n1. **[error]** a.txt:1 — FINDING\\n"' "$1"; }
reason() { jq -r .reason <<<"$out"; }
armit() { CLAUDE_CODE_SESSION_ID=S1 bash "$arm" --base HEAD --source "make it two" --requirement-file "$tmp/req.md" "$@" >/dev/null; }

out="$(hook)"; check "not armed: allows" '[ -z "$out" ]'

armit
out="$(REVIEW_GATE_REVIEWER='exit 99' hook)"; check "armed, no changes: allows without reviewing" '[ -z "$out" ] && [ "$(cat "$st/round")" = 0 ]'

echo two > a.txt
out="$(REVIEW_GATE_REVIEWER='exit 99' hook "" S2)"; check "other session: allows" '[ -z "$out" ]'
out="$(REVIEW_GATE_INSIDE=1 REVIEW_GATE_REVIEWER='exit 99' hook)"; check "inside the reviewer: allows" '[ -z "$out" ]'

out="$(REVIEW_GATE_REVIEWER="$(report 'Does not meet requirement')" hook)"
check "fail verdict: blocks" '[ "$(jq -r .decision <<<"$out")" = block ]'
check "fail verdict: reason carries the report and the protocol" 'reason | grep -q FINDING && reason | grep -q "### Disputed"'
check "round 1 prompt: skill on line 1, requirement, changed file" \
  'head -1 "$st/prompt-1.md" | grep -qx "/test-first-code-review make it two" && grep -q "Make a.txt say two." "$st/prompt-1.md" && grep -q "a.txt" "$st/prompt-1.md"'
check "still armed after a fail" '[ -f "$st/armed" ]'

out="$(REVIEW_GATE_REVIEWER="$(report 'Meets requirement, fixes required')" hook "### Disputed
- FINDING: wrong because XYZZY")"
check "round 2 prompt carries the implementer's reply" 'grep -q XYZZY "$st/prompt-2.md"'
check "fixes-required verdict: blocks" '[ "$(jq -r .decision <<<"$out")" = block ] && [ -f "$st/armed" ]'

out="$(REVIEW_GATE_REVIEWER="$(report 'Meets requirement')" hook)"
check "pass verdict: one last block, then disarmed" '[ "$(jq -r .decision <<<"$out")" = block ] && [ ! -f "$st/armed" ]'
check "rounds log" '[ "$(wc -l < "$st/rounds.tsv")" = 3 ] && grep -q "^3	custom	Meets requirement — reason" "$st/rounds.tsv"'
out="$(REVIEW_GATE_REVIEWER='exit 99' hook)"; check "after pass: allows" '[ -z "$out" ]'

armit
out="$(REVIEW_GATE_REVIEWER="$(report 'Cannot determine')" hook)"
check "cannot determine: disarms" '[ ! -f "$st/armed" ] && reason | grep -q "couldn.t run"'

armit
out="$(REVIEW_GATE_REVIEWER='cat >/dev/null; echo hacked >> a.txt; printf "## Verdict\nMeets requirement\n"' hook)"
check "reviewer touched the tree: disarms and says so" '[ ! -f "$st/armed" ] && reason | grep -q "changed the working tree"'
echo two > a.txt

armit
out="$(REVIEW_GATE_REVIEWER='cat >/dev/null; echo oops >&2; exit 3' hook)"
check "reviewer failed: disarms, names exit status" '[ ! -f "$st/armed" ] && reason | grep -q "exit 3"'

armit
out="$(REVIEW_GATE_REVIEWER='cat >/dev/null; echo no verdict here' hook)"
check "no verdict: disarms" '[ ! -f "$st/armed" ] && reason | grep -q "no verdict"'

armit
out="$(REVIEW_GATE_REVIEWER='cat >/dev/null; printf "• ## Verdict\n• Does not meet requirement — x\n"' hook)"
check "verdict with a UI prefix still parses" 'reason | grep -q "): Does not meet requirement"'

armit --max-rounds 1
REVIEW_GATE_REVIEWER="$(report 'Does not meet requirement')" hook >/dev/null
out="$(REVIEW_GATE_REVIEWER='exit 99' hook)"
check "round limit: last block, disarms, no review" '[ ! -f "$st/armed" ] && reason | grep -q "after 1 rounds"'

armit
start=$(date +%s)
out="$(REVIEW_GATE_TIMEOUT=2 REVIEW_GATE_REVIEWER='cat >/dev/null; sleep 30' hook)"
check "reviewer timeout: killed by the gate, disarms" '[ $(( $(date +%s) - start )) -lt 10 ] && [ ! -f "$st/armed" ] && reason | grep -q failed'

armit
jq -n '{session_id:"S1"}' | REVIEW_GATE_REVIEWER="cat >/dev/null; echo \$\$ > $tmp/rpid; sleep 30" "$gate" > "$tmp/out" &
gpid=$!; for _ in $(seq 50); do [ -s "$tmp/rpid" ] && break; sleep 0.1; done
kill -TERM "$gpid"; wait "$gpid"; sleep 0.5
check "SIGTERM (Esc): reviewer killed, gate disarmed, no block" \
  'gone "$(cat "$tmp/rpid")" && [ ! -f "$st/armed" ] && [ ! -s "$tmp/out" ]'

echo; echo "$pass passed, $fail failed"; [ "$fail" -eq 0 ]
