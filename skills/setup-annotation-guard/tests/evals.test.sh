#!/usr/bin/env bash
# Offline checks for the behaviour evals in tests/evals/. The evals are billed
# model runs (see CLAUDE.md); this runs no model. It checks every case is in
# the shape `claude plugin eval` loads (skills-audit's check-evals.py), and
# that each fixture is what its case and graders say: the comment counts the
# graders quote, which comments are directives, the tests passing, the dirty
# tree, the installed rule, and a post-check that fails before any setup.
# Needs ast-grep on PATH or AST_GREP=<path>, as the skill itself does.
#
#   bash skills/setup-annotation-guard/tests/evals.test.sh
set -uo pipefail

TESTS="$(cd "$(dirname "$0")" && pwd)"
EVALS="$TESTS/evals"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0
ok()   { pass=$((pass + 1)); echo "  ok   $1"; }
bad()  { fail=$((fail + 1)); echo "  FAIL $1 — got: $2"; }

sg_bin="$(command -v "${AST_GREP:-ast-grep}" || true)"
if [ -z "$sg_bin" ]; then
  echo "ast-grep not found. Install it, or set AST_GREP to its path." >&2
  exit 1
fi
mkdir -p "$WORK/bin" && ln -s "$sg_bin" "$WORK/bin/ast-grep"
export PATH="$WORK/bin:$PATH"

echo "format"
while IFS='|' read -r verdict name why; do
  if [ "$verdict" = ok ]; then ok "$name"; else bad "$name" "$why"; fi
done < <(python3 "$TESTS/../../skills-audit/scripts/check-evals.py" "$(dirname "$TESTS")")

# build <case> — scaffold the case in $WORK/<case> as a run would. Prints it.
build() {
  local repo="$WORK/$1"
  mkdir -p "$repo"
  (cd "$repo" && bash "$EVALS/$1/place-files.sh") >/dev/null 2>&1 || return 1
  echo "$repo"
}

# count <repo> <language> <path>... — comments ast-grep finds there.
count() {
  local repo="$1" lang="$2"; shift 2
  (cd "$repo" && ast-grep scan --no-ignore hidden --globs '!.git' \
    --inline-rules "{id: c, language: $lang, rule: {kind: comment}}" --json=stream "$@" 2>/dev/null | wc -l | tr -d ' ')
}

for case_dir in "$EVALS"/*/; do
  c="$(basename "$case_dir")"
  case "$c" in results | benchmarks | mocks) continue ;; esac
  echo "$c"
  repo="$(build "$c")" || { bad "$c: scaffolds" "place-files.sh failed"; continue; }
  [ "$(git -C "$repo" rev-list --count HEAD)" = 1 ] && [ "$(git -C "$repo" branch --show-current)" = main ] \
    && ok "$c: one commit on main" || bad "$c: one commit on main" "$(git -C "$repo" log --oneline)"
  out="$(cd "$repo" && PYTHONDONTWRITEBYTECODE=1 make -s test 2>&1)" \
    && ok "$c: make test passes" || bad "$c: make test" "$out"

  case "$c" in
    dirty-tree-stops)
      st="$(git -C "$repo" status --porcelain)"
      [ "$st" = " M notes/store.py" ] && ok "$c: the only change is an uncommitted edit to notes/store.py" \
        || bad "$c: dirty tree" "$st"
      ;;
    already-installed-stops)
      [ -z "$(git -C "$repo" status --porcelain)" ] && git -C "$repo" ls-files --error-unmatch rules/no-comments-python.yml sgconfig.yml >/dev/null 2>&1 \
        && ok "$c: clean, with no-comments-python committed" || bad "$c: installed rule" "$(git -C "$repo" ls-files)"
      ;;
    asks-once-with-counts | full-setup-with-answers)
      [ -z "$(git -C "$repo" status --porcelain)" ] && ok "$c: clean tree" || bad "$c: clean tree" "$(git -C "$repo" status --porcelain)"
      got="$(count "$repo" Python notes scripts tests) $(count "$repo" TypeScript web) $(count "$repo" YAML .github) $(count "$repo" Python vendor)"
      [ "$got" = "6 3 1 2" ] && ok "$c: comments: 6 Python, 3 TypeScript, 1 YAML, 2 in vendor/" \
        || bad "$c: comment counts (Python TypeScript YAML vendor)" "$got"
      docs="$(python3 -c 'import ast,sys
t=ast.parse(open(sys.argv[1]).read())
print(sum(1 for n in ast.walk(t) if isinstance(n,(ast.Module,ast.FunctionDef)) and ast.get_docstring(n)))' "$repo/notes/store.py")"
      jsdoc="$(grep -c '^/\*\*' "$repo/web/format.ts")"
      [ "$docs $jsdoc" = "2 1" ] && ok "$c: 2 Python docstrings, 1 JSDoc comment" || bad "$c: doc comments" "$docs $jsdoc"
      [ "$(head -1 "$repo/scripts/export.py")" = "#!/usr/bin/env python3" ] && grep -q '\[tool.ruff\]' "$repo/pyproject.toml" \
        && grep -q '# noqa: E501' "$repo/notes/store.py" && ok "$c: a shebang, and a noqa that ruff's config makes a directive" \
        || bad "$c: directives" "see fixture"
      ! ls "$repo" | grep -qiE '^\.?eslint' && ! grep -q eslint "$repo/README.md" && grep -q 'eslint-disable-next-line' "$repo/web/format.ts" \
        && ok "$c: an eslint-disable with no ESLint configured" || bad "$c: eslint" "$(ls -a "$repo")"
      [ "$(grep -c '^#' "$repo/Makefile") $(grep -c '^#' "$repo/pyproject.toml")" = "1 1" ] \
        && ok "$c: one comment each in the Makefile and pyproject.toml" || bad "$c: unguarded comments" "see fixture"
      if [ "$c" = full-setup-with-answers ]; then
        res="$(cd "$repo" && bash "$EVALS/$c/post-check.sh" 2>&1)"
        oks="$(printf '%s\n' "$res" | grep -c '^ok')"
        printf '%s\n' "$res" | grep -q '^ok   make test passes$' && printf '%s\n' "$res" | grep -q '^FAIL a lint target exists and passes$' \
          && [ "$(printf '%s\n' "$res" | grep -c '^FAIL')" -ge 10 ] \
          && ok "$c: post-check fails before any setup ($oks of $(printf '%s\n' "$res" | wc -l | tr -d ' ') checks hold already)" \
          || bad "$c: post-check before setup" "$res"
        [ -z "$(git -C "$repo" status --porcelain)" ] || bad "$c: post-check left the tree clean" "$(git -C "$repo" status --porcelain)"
      fi
      ;;
    *)
      bad "$c: has a premise check here" "add one for this case"
      ;;
  esac
done

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
