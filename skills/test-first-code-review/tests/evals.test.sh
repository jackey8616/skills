#!/usr/bin/env bash
# Offline checks for the behaviour evals in tests/evals/. The evals themselves
# are billed model runs (see CLAUDE.md); this runs no model. It checks that
# every case is in the shape `claude plugin eval` loads (skills-audit's
# check-evals.py), and that each
# fixture is what its case says it is: which tests pass and which fail, on
# the base revision and on the change. A fixture that drifted from its case
# would make the model's score meaningless.
#
#   bash skills/test-first-code-review/tests/evals.test.sh
set -uo pipefail

TESTS="$(cd "$(dirname "$0")" && pwd)"
EVALS="$TESTS/evals"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0
ok()   { pass=$((pass + 1)); echo "  ok   $1"; }
bad()  { fail=$((fail + 1)); echo "  FAIL $1 — got: $2"; }

echo "format"
while IFS='|' read -r verdict name why; do
  if [ "$verdict" = ok ]; then ok "$name"; else bad "$name" "$why"; fi
done < <(python3 "$TESTS/../../skills-audit/scripts/check-evals.py" "$(dirname "$TESTS")")

# build <case> — scaffold the case into $WORK/<case>, as the eval run would,
# and extract its base revision into $WORK/<case>-base. Prints the repo path.
build() {
  local repo="$WORK/$1"
  mkdir -p "$repo" "$repo-base"
  (cd "$repo" && bash "$EVALS/$1/place-files.sh") >/dev/null 2>&1 || return 1
  git -C "$repo" archive main | tar -x -C "$repo-base"
  echo "$repo"
}

# run_tests <dir> — the fixture's own test command. Output in $OUT, exit in $RC.
run_tests() {
  RC=0
  OUT="$(cd "$1" && PYTHONDONTWRITEBYTECODE=1 make -s test 2>&1)" || RC=$?
}

# with_head_tests <case> — the base revision's code with the change's tests/.
with_head_tests() {
  rm -rf "$WORK/$1-base/tests" && cp -R "$WORK/$1/tests" "$WORK/$1-base/tests"
}

for case_dir in "$EVALS"/*/; do
  c="$(basename "$case_dir")"
  [ "$c" = results ] && continue
  echo "$c"
  repo="$(build "$c")" || { bad "$c: scaffolds" "place-files.sh failed"; continue; }
  branch="$(git -C "$repo" branch --show-current)"
  ahead="$(git -C "$repo" rev-list --count main..HEAD)"
  [ "$branch" != main ] && [ "$ahead" = 1 ] && [ -z "$(git -C "$repo" status --porcelain)" ] \
    && ok "$c: scaffolds a clean branch one commit ahead of main" \
    || bad "$c: scaffolds" "branch $branch, $ahead ahead, status: $(git -C "$repo" status --porcelain)"
  run_tests "$repo-base"
  [ "$RC" -eq 0 ] && ok "$c: the base revision's own tests pass" || bad "$c: base tests" "$OUT"

  case "$c" in
    no-tests-fails-fast)
      changed="$(git -C "$repo" diff --name-only main...HEAD)"
      [ "$changed" = durations.py ] && ok "$c: the change touches durations.py and no test" \
        || bad "$c: changed files" "$changed"
      ;;
    test-passes-without-change)
      run_tests "$repo"
      [ "$RC" -eq 0 ] && ok "$c: the change's tests pass" || bad "$c: head tests" "$OUT"
      with_head_tests "$c"; run_tests "$repo-base"
      [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q '^test_hours_and_seconds .* ok$' \
        && ok "$c: test_hours_and_seconds passes on the base revision too" || bad "$c: new test on base" "$OUT"
      ;;
    missing-dependency-cannot-determine)
      if python3 -c 'import acme_testkit' 2>/dev/null; then
        bad "$c: acme_testkit is missing here" "it imports, so the case can't test a missing dependency"
      else
        run_tests "$repo"
        [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q "No module named 'acme_testkit'" \
          && ok "$c: the change's test fails to import acme_testkit" || bad "$c: import failure" "exit $RC: $OUT"
      fi
      ;;
    feature-with-tests-meets)
      run_tests "$repo"
      [ "$RC" -eq 0 ] && ok "$c: the change's tests pass" || bad "$c: head tests" "$OUT"
      with_head_tests "$c"; run_tests "$repo-base"
      [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q '^test_days .* ERROR$' \
        && printf '%s' "$OUT" | grep -q '^test_days_and_hours .* ERROR$' \
        && ok "$c: both new tests fail on the base revision" || bad "$c: new tests on base" "$OUT"
      ;;
    reports-files-tests-leave)
      run_tests "$repo"
      left="$(git -C "$repo" status --porcelain)"
      [ "$RC" -eq 0 ] && [ "$left" = "?? last_run.txt" ] \
        && ok "$c: the tests pass and leave only last_run.txt behind" || bad "$c: left behind" "exit $RC, status: $left"
      ;;
    *)
      bad "$c: has a premise check here" "add one for this case"
      ;;
  esac
done

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
