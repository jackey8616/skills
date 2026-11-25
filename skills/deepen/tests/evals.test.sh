#!/usr/bin/env bash
# Offline checks for the behaviour evals in tests/evals/. The evals are billed
# model runs (see CLAUDE.md); this runs no model. deepen works on text alone,
# so the cases have no fixtures. This checks every case is in the shape
# `claude plugin eval` loads (skills-audit's check-evals.py), and that its
# prompt is the one its case is about: no arguments for the empty-arguments
# case, a prompt to deepen for the rest.
#
#   bash skills/deepen/tests/evals.test.sh
set -uo pipefail

TESTS="$(cd "$(dirname "$0")" && pwd)"
EVALS="$TESTS/evals"

pass=0
fail=0
ok()   { pass=$((pass + 1)); echo "  ok   $1"; }
bad()  { fail=$((fail + 1)); echo "  FAIL $1 — got: $2"; }

echo "format"
while IFS='|' read -r verdict name why; do
  if [ "$verdict" = ok ]; then ok "$name"; else bad "$name" "$why"; fi
done < <(python3 "$TESTS/../../skills-audit/scripts/check-evals.py" "$(dirname "$TESTS")")

# prompt_of <case> — the prompt in its prompt.md, settings block left out.
prompt_of() {
  python3 -c 'import re,sys; print(re.match(r"---\n.*?\n---\n(.*)", open(sys.argv[1]).read(), re.S).group(1).strip())' \
    "$EVALS/$1/prompt.md"
}

echo "prompts"
for case_dir in "$EVALS"/*/; do
  c="$(basename "$case_dir")"
  case "$c" in results | benchmarks | mocks) continue ;; esac
  p="$(prompt_of "$c")"
  case "$c" in
    empty-arguments-asks)
      [ "$p" = /deepen ] && ok "$c: /deepen with no arguments" || bad "$c: no arguments" "$p" ;;
    answers-four-questions-first | rewrites-not-executes)
      [ -n "${p#/deepen }" ] && [ "${p#/deepen }" != "$p" ] && ok "$c: /deepen with a prompt to deepen" \
        || bad "$c: a prompt to deepen" "$p" ;;
    *)
      bad "$c: has a prompt check here" "add one for this case" ;;
  esac
done

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
