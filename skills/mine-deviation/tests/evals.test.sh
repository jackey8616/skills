#!/usr/bin/env bash
# Offline checks for the behaviour evals in tests/evals/. The evals themselves
# are billed model runs (see CLAUDE.md); this runs no model. It checks that
# every case is in the shape `claude plugin eval` loads (skills-audit's
# check-evals.py), that each fixture is what its case says, and that each
# post-check.sh passes on the untouched fixture and fails once the thing it
# guards is changed.
#
#   bash skills/mine-deviation/tests/evals.test.sh
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

# build <case> — scaffold a fresh copy of the case's project. Prints its path.
build() {
  local dir
  dir="$(mktemp -d "$WORK/$1-XXXX")"
  (cd "$dir" && bash "$EVALS/$1/place-files.sh") >/dev/null 2>&1 || return 1
  echo "$dir"
}

# post <case> <dir> — the case's post-check on <dir>. Output in $OUT, exit in $RC.
post() {
  RC=0
  OUT="$(cd "$2" && bash "$EVALS/$1/post-check.sh" 2>&1)" || RC=$?
}

# guards <case> <what> <command run in a fresh project> <FAIL line expected>
guards() {
  local dir
  dir="$(build "$1")" || { bad "$1: scaffolds" "place-files.sh failed"; return; }
  (cd "$dir" && eval "$3") >/dev/null 2>&1
  post "$1" "$dir"
  [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -qF "FAIL $4" \
    && ok "$1: post-check fails when $2" || bad "$1: post-check on $2" "$OUT"
}

# tests_in <dir> <make target> — app/'s tests fail on test_keeps_hyphens alone.
tests_in() {
  local out rc=0
  out="$(cd "$1/app" && PYTHONDONTWRITEBYTECODE=1 make -s "$2" 2>&1)" || rc=$?
  [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q '^test_keeps_hyphens .* FAIL$' \
    && [ "$(printf '%s' "$out" | grep -c ' \.\.\. FAIL$')" = 1 ]
}

remote_is() { [ "$(git -C "$1" remote get-url origin 2>/dev/null)" = "https://github.com/example-skills-org/$2.git" ]; }

for case_dir in "$EVALS"/*/; do
  c="$(basename "$case_dir")"
  [ "$c" = results ] && continue
  echo "$c"
  body="$(awk 'seen >= 2 && NF; /^---$/ { seen++ }' "$case_dir/prompt.md")"

  if [ "$c" = empty-arguments-asks ]; then
    [ "$body" = /mine-deviation ] && ok "$c: the prompt is the bare command" || bad "$c: prompt" "$body"
    [ ! -e "$case_dir/place-files.sh" ] && ok "$c: no fixture, so nothing holds a deviation" || bad "$c: fixture" "has place-files.sh"
    continue
  fi

  dir="$(build "$c")" || { bad "$c: scaffolds" "place-files.sh failed"; continue; }
  post "$c" "$dir"
  [ "$RC" -eq 0 ] && ok "$c: post-check passes on the untouched fixture" || bad "$c: post-check" "$OUT"
  remote_is "$dir/app" slug-app && ok "$c: app/ has its GitHub remote" || bad "$c: app/ remote" "$(git -C "$dir/app" remote -v)"
  grep -q 'py_compile' "$dir/app/.github/workflows/ci.yml" && ! grep -q 'make\|unittest' "$dir/app/.github/workflows/ci.yml" \
    && ok "$c: app/'s CI compiles and runs no tests" || bad "$c: app/ CI" "$(cat "$dir/app/.github/workflows/ci.yml")"

  if [ "$c" = repo-mismatch-repo-only ]; then
    tests_in "$dir" check && ok "$c: make check fails on test_keeps_hyphens alone" || bad "$c: make check" "wrong result"
    ! (cd "$dir/app" && make -s test >/dev/null 2>&1) && grep -q 'make check' "$dir/app/README.md" \
      && ok "$c: app/ has no test target, and its README names make check" || bad "$c: make test" "it runs"
  else
    tests_in "$dir" test && ok "$c: make test fails on test_keeps_hyphens alone" || bad "$c: make test" "wrong result"
  fi
  guards "$c" "app/ gets a commit" 'echo x >> app/slug.py && cd app && git -c user.name=a -c user.email=a@a commit -qam fix' "app/ is unchanged"
  guards "$c" "app/ gets an ignored file" 'echo x > app/notes.pyc && printf "*.pyc\n" >> app/.git/info/exclude' "app/ is unchanged"

  case "$c" in
    no-source-reports)
      [ ! -e "$dir/skills-src" ] && [ -z "$(find "$dir" -name '.*-skills' -type f)" ] \
        && ok "$c: ship-check is installed by hand, with no manifest and no source checkout" || bad "$c: install" "$(ls -A "$dir")"
      guards "$c" "the installed openai.yaml is edited" 'echo x >> installed/ship-check/agents/openai.yaml' "installed/ship-check is unchanged"
      guards "$c" "a file is added to the installed skill" 'echo x > installed/ship-check/NOTES.md' "installed/ship-check is unchanged"
      ;;
    repairs-task-first|routes-both|repo-mismatch-repo-only|follows-issue-template)
      remote_is "$dir/skills-src" skills && [ -n "$(git -C "$dir/skills-src" ls-files skills/ship-check/SKILL.md)" ] \
        && ok "$c: skills-src/ holds ship-check, with its GitHub remote" || bad "$c: skills-src/" "$(git -C "$dir/skills-src" remote -v)"
      [ -z "$(git -C "$dir/skills-src" ls-files 'skills/ship-check/tests')" ] \
        && ok "$c: ship-check has no evals of its own to distract a run" || bad "$c: ship-check tests" "present"
      guards "$c" "skills-src/ gets a branch" 'git -C skills-src branch fix' "skills-src/ is unchanged"
      guards "$c" "the skill is edited" 'echo x >> skills-src/skills/ship-check/SKILL.md' "skills-src/ is unchanged"
      ;;
    *)
      bad "$c: has a premise check here" "add one for this case"
      ;;
  esac

  case "$c" in
    routes-both)
      grep -q 'billing.internal.acme-corp.net' "$case_dir/prompt.md" && ok "$c: the prompt names the private host" || bad "$c: prompt" "no host"
      guards "$c" "the host is written into the project" 'echo billing.internal.acme-corp.net > leak.md' "no file in the project names"
      ;;
    follows-issue-template)
      t="$dir/skills-src/.github/ISSUE_TEMPLATE/deviation.md"
      [ "$(grep '^## ' "$t" | tr '\n' '|')" = '## Observed|## Expected by the SOP|## Suspected cause|## How to reproduce|' ] \
        && grep -q '^labels: deviation$' "$t" \
        && ok "$c: the template has the four headings and the deviation label" || bad "$c: template" "$(cat "$t")"
      ;;
    repo-mismatch-repo-only)
      ! grep -q 'make check' "$case_dir/prompt.md" && ok "$c: the prompt doesn't give away make check" || bad "$c: prompt" "names make check"
      ;;
  esac
done

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
