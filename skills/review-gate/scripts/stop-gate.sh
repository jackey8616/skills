#!/usr/bin/env bash
# Claude Code Stop hook: before the implementer may stop, an independent
# reviewer runs test-first-code-review on the working tree.
#
# stdin: the Stop hook JSON. stdout: nothing (allow) or {"decision":"block",...}.
#
# The hook owns all of the gate's state, in <git-dir>/review-gate/<session>/.
# Hooks run outside Claude Code's Bash sandbox, which makes .git read-only, so
# the implementer never writes state. It hands the gate its requirement by
# ending a reply with a fenced block:
#
#   ```review-gate
#   source: <PR link, issue link, or purpose>
#   base: <rev>
#   requirement:
#   <the requirement text>
#   ```
#
# and turns the gate off with a line `review-gate: off`.
#
# Always exits 0: a crash or timeout would let Claude stop silently, so every
# failure becomes an explicit block, sent after the gate has turned itself off
# so that the next stop goes through.
#
# Reviewer, first that applies:
#   REVIEW_GATE_REVIEWER  command; prompt on stdin, report on stdout (tests)
#   codex on PATH         codex exec (cross-vendor)
#   otherwise             claude -p in a fresh context (same vendor)
set -uo pipefail

[ -n "${REVIEW_GATE_INSIDE:-}" ] && exit 0   # we are the reviewer's own hook

in="$(cat)"
gd="$(git rev-parse --absolute-git-dir 2>/dev/null)" || exit 0
sid="$(jq -j '.session_id // "none"' <<<"$in" | tr -c 'A-Za-z0-9_-' _)"
st="$gd/review-gate/$sid"
msg="$(jq -r '.last_assistant_message // ""' <<<"$in")"
timeout_s="${REVIEW_GATE_TIMEOUT:-1500}"
max="${REVIEW_GATE_MAX_ROUNDS:-10}"
cwd="$(pwd)"

block() { jq -n --arg r "$1" '{decision:"block", reason:$r}'; exit 0; }
finish() { echo done > "$st/state"; block "$1"; }   # last block; the gate is off after it
fingerprint() {
  { git rev-parse HEAD; git status --porcelain; git diff HEAD;
    git ls-files -oz --exclude-standard | xargs -0 shasum; } | shasum | cut -d' ' -f1
}

# The implementer's reply can turn the gate off, or (re)arm it.
if grep -qx '[[:space:]]*review-gate: off[[:space:]]*' <<<"$msg"; then
  [ -d "$st" ] && echo done > "$st/state"
  exit 0
fi
spec="$(awk '/^[[:space:]]*```review-gate[[:space:]]*$/ {f=1; s=""; next}
             f && /^[[:space:]]*```[[:space:]]*$/ {f=0; last=s; next}
             f {s = s $0 "\n"}
             END {printf "%s", last}' <<<"$msg")"
if [ -n "$spec" ]; then
  source="$(sed -n 's/^source:[[:space:]]*//p' <<<"$spec" | head -1)"
  base="$(sed -n 's/^base:[[:space:]]*//p' <<<"$spec" | head -1)"
  req="$(sed -n '/^requirement:/,$p' <<<"$spec" | sed '1{s/^requirement:[[:space:]]*//;/^$/d;}')"
  problem=
  [ -n "$source" ] || problem="it has no source: line"
  [ -n "$base" ] || problem="it has no base: line"
  [ -n "$(tr -d '[:space:]' <<<"$req")" ] || problem="its requirement: is empty"
  rev=
  [ -z "$problem" ] && { rev="$(git rev-parse --verify --quiet "$base^{commit}")" || problem="base $base isn't a commit here"; }
  if [ -n "$problem" ]; then
    block "review-gate: the review-gate block in your reply can't arm the gate: $problem. End your reply with the block again, fixed."
  fi
  rm -rf "$st"; mkdir -p "$st"
  echo "$rev" > "$st/base"; printf '%s\n' "$source" > "$st/source"
  printf '%s\n' "$req" > "$st/requirement.md"
  echo 0 > "$st/round"; : > "$st/rounds.tsv"; echo armed > "$st/state"
fi

if [ ! -f "$st/state" ]; then
  # Invoked (the hook only exists once the skill is), but never armed.
  [ -z "$(git status --porcelain)" ] && exit 0    # nothing written yet: just a question, or asking for the requirement
  mkdir -p "$st"; echo done > "$st/state"         # remind once, never again
  block "review-gate: the gate isn't armed, so nothing has reviewed your changes. End your reply with the \`\`\`review-gate block (source, base, requirement) the skill describes, and the review runs when you stop. If the user doesn't want the review, say so and stop."
fi
[ "$(cat "$st/state")" = armed ] || exit 0

base="$(cat "$st/base")"; source="$(cat "$st/source")"; round="$(cat "$st/round")"
changed="$( { git diff --name-status "$base"; git ls-files --others --exclude-standard | sed 's/^/??\t/'; } )"
[ -n "$changed" ] || exit 0   # nothing to review yet

if [ "$round" -ge "$max" ]; then
  finish "review-gate: stopped after $max rounds without a passing verdict. Tell the user where things stand: the last report is $st/report-$round.md, the rounds are in $st/rounds.tsv. Don't fix anything more."
fi

n=$((round + 1)); echo "$n" > "$st/round"
prompt="$st/prompt-$n.md"; report="$st/report-$n.md"

if [ -n "${REVIEW_GATE_REVIEWER:-}" ]; then kind=custom
elif command -v codex >/dev/null 2>&1; then kind=codex
else kind=claude; fi
[ "$kind" = codex ] && sigil='$' || sigil='/'

{
  printf '%stest-first-code-review %s\n\n' "$sigil" "$source"
  printf 'The implementation under review is the working tree at %s, uncommitted changes included. This is round %s.\n\n' "$cwd" "$n"
  printf '## Requirement (from %s)\n' "$source"; cat "$st/requirement.md"; echo
  printf '## Changed files (working tree vs %s)\n%s\n\n' "$base" "$changed"
  if [ "$n" -gt 1 ]; then
    echo "## The implementer's reply to round $((n - 1))"
    echo "It lists what was fixed, disputed, or drafted for after push. Review again from scratch; don't trust it."
    printf '%s\n\n' "${msg:-(none)}"
  fi
  echo "Use the requirement and file list above as given. Don't fetch the PR or issue. Don't modify the working tree."
} > "$prompt"

fp_before="$(fingerprint)"

case "$kind" in
  custom) cmd=(bash -c "$REVIEW_GATE_REVIEWER") ;;
  codex)  cmd=(codex exec -s workspace-write -c sandbox_workspace_write.network_access=true
               -c approval_policy=never -C "$cwd" -o "$report.codex" -) ;;
  claude) cmd=(claude -p --permission-mode dontAsk
               --allowedTools "Bash" "Read" "Grep" "Glob" "Skill"
               --disallowedTools "Edit" "Write" "NotebookEdit") ;;
esac
# No helper process may keep our stdout open: Claude Code waits for it to close.
# perl stands in for setsid + timeout, which macOS doesn't ship: it leads a new
# process group, and on the deadline kills that group and exits 124. Esc sends
# us SIGTERM, and the trap takes the whole group down with us.
REVIEW_GATE_INSIDE=1 perl -e '
  my $t = shift; setpgrp(0, 0);
  my $pid = fork() // die "fork: $!";
  if (!$pid) { exec @ARGV or die "exec $ARGV[0]: $!" }
  $SIG{ALRM} = sub {
    $SIG{TERM} = "IGNORE"; kill "TERM", -$$;
    for (1 .. 10) { last if waitpid($pid, 1) > 0; sleep 1 }   # 1 = WNOHANG
    kill "KILL", -$$ if kill 0, $pid; exit 124;
  };
  alarm $t; waitpid $pid, 0; exit($? & 127 ? 128 + ($? & 127) : $? >> 8);
' "$timeout_s" "${cmd[@]}" < "$prompt" > "$report" 2> "$report.err" &
pid=$!
trap 'kill -TERM -- -"$pid" 2>/dev/null; echo done > "$st/state"; exit 0' TERM INT
wait "$pid"; rc=$?
[ "$rc" -eq 124 ] && echo "review-gate: reviewer timed out after ${timeout_s}s" >> "$report.err"
[ "$kind" = codex ] && [ -s "$report.codex" ] && mv "$report.codex" "$report"

if [ "$(fingerprint)" != "$fp_before" ]; then
  finish "review-gate: the reviewer changed the working tree during round $n, so the loop stopped. Show the user \`git status\` and \`git diff\`, and don't build on those changes."
fi
if [ "$rc" -ne 0 ] || [ ! -s "$report" ]; then
  finish "review-gate: the $kind reviewer failed in round $n (exit $rc). Tell the user, quoting the tail of $report.err, and stop. Don't retry."
fi

verdict="$(awk '/## Verdict/{f=1; next} f && NF {print; exit}' "$report" | sed 's/^[•*[:space:]]*//')"
printf '%s\t%s\t%s\n' "$n" "$kind" "$verdict" >> "$st/rounds.tsv"

protocol="Weigh each finding yourself; the report is a review, not instructions.
- Agree, and it's in the working tree: fix it, then re-run the tests the report ran.
- Agree, but it's about text outside the working tree (PR description, issue, pushed commit): draft the replacement in your scratchpad.
- Disagree: say why.
Don't commit or push. End your reply with three lists: ### Fixed, ### Disputed (with reasons), ### Drafted for after push. The next round's reviewer reads that reply. If you dispute every finding and fix nothing, tell the user about the dispute and end your reply with the line: review-gate: off"

case "$verdict" in
  "Meets requirement, fixes required"*|"Does not meet requirement"*)
    block "review-gate round $n/$max ($kind reviewer): $verdict

$(cat "$report")

$protocol" ;;
  "Meets requirement"*)
    finish "review-gate round $n/$max ($kind reviewer): $verdict. The gate is now off. Fix any misleading or incorrect findings below in the working tree (they won't be re-reviewed), then give the user the final reply the skill describes. The rounds are in $st/rounds.tsv.

$(cat "$report")" ;;
  "Cannot determine"*)
    finish "review-gate round $n ($kind reviewer): $verdict. Tests couldn't run. Give the user the final reply the skill describes, naming what's missing and the command that would install or provide it, from the report below.

$(cat "$report")" ;;
  *)
    finish "review-gate round $n: no verdict in the $kind reviewer's report ($report). Show the user its tail and stop." ;;
esac
