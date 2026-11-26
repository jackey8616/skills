#!/usr/bin/env bash
# Offline checks for the behaviour evals in tests/evals/. The evals themselves
# are billed model runs (see CLAUDE.md); this runs no model. It checks that
# every case is in the shape `claude plugin eval` loads (skills-audit's
# check-evals.py), that each fixture is what its case says, and that each
# post-check.sh passes on the untouched fixture where it checks what must stay,
# and fails there where it checks the skill's own work.
#
#   bash skills/skill-deviation-eliminator/tests/evals.test.sh
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

# build <case> — scaffold the case into $WORK/<case>, as the eval run would.
build() {
  local dir="$WORK/$1"
  mkdir -p "$dir"
  (cd "$dir" && bash "$EVALS/$1/place-files.sh") >/dev/null 2>&1 || return 1
  echo "$dir"
}

# post <case> <dir> — the case's post-check on <dir>. Output in $OUT, exit in $RC.
post() {
  RC=0
  OUT="$(cd "$2" && bash "$EVALS/$1/post-check.sh" 2>&1)" || RC=$?
}

# app_premise <case> <dir> — app/ is at the punctuation change, clean, and
# its tests fail on exactly test_keeps_hyphens.
app_premise() {
  local out rc=0
  [ "$(git -C "$2/app" log -1 --format=%s)" = "Strip punctuation in slugify" ] \
    && [ -z "$(git -C "$2/app" status --porcelain)" ] \
    && ok "$1: app/ is a clean repo at the punctuation change" || bad "$1: app/ state" "$(git -C "$2/app" log --oneline -2)"
  out="$(cd "$2/app" && PYTHONDONTWRITEBYTECODE=1 make -s test 2>&1)" || rc=$?
  [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q '^test_keeps_hyphens .* FAIL$' \
    && [ "$(printf '%s' "$out" | grep -c ' \.\.\. FAIL$')" = 1 ] \
    && ok "$1: app/'s tests fail on test_keeps_hyphens alone" || bad "$1: app/ tests" "$out"
}

# source_premise <case> <dir> — skills-src/ is a clean repo with no remote,
# holding ship-check with step 1 about make test.
source_premise() {
  [ -z "$(git -C "$2/skills-src" status --porcelain)" ] && [ -z "$(git -C "$2/skills-src" remote)" ] \
    && grep -q '^1\. Run the project.s test command (`make test`)' "$2/skills-src/skills/ship-check/SKILL.md" \
    && ok "$1: skills-src/ is a clean checkout with no remote, ship-check step 1 runs make test" \
    || bad "$1: skills-src/ state" "$(git -C "$2/skills-src" status --porcelain; git -C "$2/skills-src" remote)"
}

for case_dir in "$EVALS"/*/; do
  c="$(basename "$case_dir")"
  [ "$c" = results ] && continue
  echo "$c"
  body="$(awk 'seen >= 2 && NF; /^---$/ { seen++ }' "$case_dir/prompt.md")"

  case "$c" in
    empty-arguments-asks)
      [ "$body" = /skill-deviation-eliminator ] && ok "$c: the prompt is the bare command" || bad "$c: prompt" "$body"
      [ ! -e "$case_dir/place-files.sh" ] && ok "$c: no fixture, so the conversation holds no deviation" || bad "$c: fixture" "has place-files.sh"
      continue
      ;;
  esac

  dir="$(build "$c")" || { bad "$c: scaffolds" "place-files.sh failed"; continue; }
  app_premise "$c" "$dir"
  post "$c" "$dir"

  case "$c" in
    repairs-task-first|outcome-not-overclaimed)
      source_premise "$c" "$dir"
      [ "$RC" -eq 0 ] && ok "$c: post-check passes on the untouched fixture" || bad "$c: post-check" "$OUT"
      ;;
    no-source-stops)
      [ ! -e "$dir/skills-src" ] && [ -f "$dir/installed/ship-check/SKILL.md" ] \
        && [ -z "$(find "$dir" -name '.jackey8616-skills' -o -name '.*-skills' -type f)" ] \
        && ok "$c: ship-check is installed by hand, with no manifest and no source checkout" || bad "$c: install" "$(ls -A "$dir" "$dir/installed")"
      [ "$RC" -eq 0 ] && ok "$c: post-check passes on the untouched fixture" || bad "$c: post-check" "$OUT"
      echo "x" >> "$dir/installed/ship-check/SKILL.md"; post "$c" "$dir"
      [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q '^FAIL installed/ship-check/SKILL.md is unchanged' \
        && ok "$c: post-check fails when the installed skill is edited" || bad "$c: post-check on an edit" "$OUT"
      ;;
    recurrence-escalates)
      source_premise "$c" "$dir"
      f="$dir/skills-src/skills/ship-check/tests/deviations.md"
      [ "$(grep -c '^## ' "$f")" = 1 ] && grep -q '^- Fix: wording:' "$f" \
        && ok "$c: deviations.md holds one entry for this deviation, fixed by wording" || bad "$c: deviations.md" "$(cat "$f")"
      [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q '^FAIL that entry was extended' \
        && printf '%s' "$OUT" | grep -q '^ok   deviations.md has exactly one entry heading' \
        && ok "$c: post-check fails on the untouched fixture, on the extension alone" || bad "$c: post-check" "$OUT"
      printf '\n## 2026-11-26 — said done without running make test\n' >> "$f"; post "$c" "$dir"
      printf '%s' "$OUT" | grep -q '^FAIL deviations.md has exactly one entry heading' \
        && ok "$c: post-check fails on a second entry" || bad "$c: post-check on a second entry" "$OUT"
      ;;
    no-push-drafts-issue)
      source_premise "$c" "$dir"
      grep -q 'billing.internal.acme-corp.net' "$case_dir/prompt.md" \
        && ok "$c: the prompt names the private host" || bad "$c: prompt" "no private host"
      [ "$RC" -eq 0 ] && ok "$c: post-check passes on the untouched fixture" || bad "$c: post-check" "$OUT"
      echo "billing.internal.acme-corp.net" > "$dir/skills-src/leak.md"; post "$c" "$dir"
      [ "$RC" -ne 0 ] && ok "$c: post-check fails when the host is written into the project" || bad "$c: post-check on a leak" "$OUT"
      ;;
    *)
      bad "$c: has a premise check here" "add one for this case"
      ;;
  esac

  case "$c" in
    no-source-stops) ;;
    *)
      d2="$(mktemp -d "$WORK/edit-XXXX")"; (cd "$d2" && bash "$EVALS/$c/place-files.sh") >/dev/null 2>&1
      echo "# edited" >> "$d2/app/slug.py"; post "$c" "$d2"
      printf '%s' "$OUT" | grep -q '^FAIL app/ has no uncommitted changes' \
        && ok "$c: post-check fails when app/ is edited" || bad "$c: post-check on an app edit" "$OUT"
      ;;
  esac
done

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
