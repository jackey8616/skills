#!/usr/bin/env bash
# Offline checks for the behaviour evals in tests/evals/. The evals themselves
# are billed model runs (see CLAUDE.md); this runs no model. It checks that
# every case is in the shape `claude plugin eval` loads (skills-audit's
# check-evals.py), and that each fixture is what its case says: a clean repo
# on main whose tests pass, or can't run, where the case needs them to.
#
#   bash skills/review-gate/tests/evals.test.sh
set -uo pipefail

TESTS="$(cd "$(dirname "$0")" && pwd)"
EVALS="$TESTS/evals"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0
ok()  { pass=$((pass + 1)); echo "  ok   $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL $1 — got: $2"; }

echo "format"
while IFS='|' read -r verdict name why; do
  if [ "$verdict" = ok ]; then ok "$name"; else bad "$name" "$why"; fi
done < <(python3 "$TESTS/../../skills-audit/scripts/check-evals.py" "$(dirname "$TESTS")")

# py <dir> <code> — run python in the fixture, as its own tests would import it.
py() { (cd "$1" && PYTHONDONTWRITEBYTECODE=1 python3 -c "$2" 2>&1); }

for case_dir in "$EVALS"/*/; do
  c="$(basename "$case_dir")"
  [ "$c" = results ] && continue
  echo "$c"
  repo="$WORK/$c"; mkdir -p "$repo"
  (cd "$repo" && bash "$case_dir/place-files.sh") >/dev/null 2>&1 \
    || { bad "$c: scaffolds" "place-files.sh failed"; continue; }
  [ "$(git -C "$repo" branch --show-current)" = main ] \
    && [ "$(git -C "$repo" rev-list --count HEAD)" = 1 ] \
    && [ -z "$(git -C "$repo" status --porcelain)" ] \
    && ok "$c: scaffolds a clean repo, one commit on main" \
    || bad "$c: scaffolds" "$(git -C "$repo" status --porcelain)"

  # The bug every case's requirement asks to fix is really there. calc in
  # cannot-determine-stops needs acme_numerics, so that check stubs it.
  stub=
  [ "$c" = cannot-determine-stops ] && stub='import sys, types; m = types.ModuleType("acme_numerics"); m.as_number = lambda x: x; sys.modules["acme_numerics"] = m
'
  out="$(py "$repo" "${stub}from calc import divide
try: divide(1, 0)
except ZeroDivisionError: print('zde')")"
  [ "$out" = zde ] && ok "$c: divide(1, 0) raises ZeroDivisionError" || bad "$c: the bug" "$out"

  case "$c" in
    loops-until-review-passes|empty-arguments-asks)
      out="$(cd "$repo" && PYTHONDONTWRITEBYTECODE=1 python3 -m unittest 2>&1)" \
        && ok "$c: the fixture's tests pass" || bad "$c: tests" "$out"
      ;;
    cannot-determine-stops)
      if py "$repo" 'import acme_numerics' >/dev/null; then
        bad "$c: acme_numerics is missing here" "it imports, so the case can't test a missing dependency"
      else
        out="$(py "$repo" 'import calc')"
        printf '%s' "$out" | grep -q "No module named 'acme_numerics'" \
          && ok "$c: calc itself can't be imported, so no test of it can run, wherever it's written" || bad "$c: import calc" "$out"
        out="$(cd "$repo" && PYTHONDONTWRITEBYTECODE=1 python3 -m unittest 2>&1)"
        printf '%s' "$out" | grep -q "No module named 'acme_numerics'" \
          && ok "$c: the fixture's tests can't run" || bad "$c: tests" "$out"
      fi
      grep -qx "acme-numerics==4.2.0" "$repo/requirements.txt" \
        && ok "$c: requirements.txt names it" || bad "$c: requirements.txt" "$(cat "$repo/requirements.txt")"
      ;;
    *) bad "$c: has fixture checks" "no case for it in evals.test.sh" ;;
  esac
done

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
