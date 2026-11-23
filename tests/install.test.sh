#!/usr/bin/env bash
# Tests for install.sh. Offline: each case installs from a local tarball
# into a throwaway $HOME, piping the script through bash like `curl | bash`.
#
#   bash tests/install.test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0
ok()   { pass=$((pass + 1)); echo "  ok   $1"; }
bad()  { fail=$((fail + 1)); echo "  FAIL $1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# archive <name> <skill>... — a tarball shaped like GitHub's, holding
# skills/<skill>/SKILL.md for each skill given.
archive() {
  local name="$1"; shift
  local dir="$WORK/src-$name/skills-test"
  mkdir -p "$dir/skills"
  for skill in "$@"; do
    mkdir -p "$dir/skills/$skill"
    echo "$skill from $name" > "$dir/skills/$skill/SKILL.md"
  done
  tar -czf "$WORK/$name.tar.gz" -C "$WORK/src-$name" skills-test
  echo "$WORK/$name.tar.gz"
}

# run <archive> [args...] — install into $H, output in $OUT, exit code in $RC.
run() {
  local arc="$1"; shift
  RC=0
  OUT="$(HOME="$H" SKILLS_ARCHIVE="$arc" bash -s -- "$@" < "$ROOT/install.sh" 2>&1)" || RC=$?
}

newhome() { H="$WORK/home-$1"; mkdir -p "$H/.claude/skills" "$H/.agents/skills"; }
C() { echo "$H/.claude/skills"; }
A() { echo "$H/.agents/skills"; }
owns() { grep -qx "$2" "$1/.jackey8616-skills"; }

V1="$(archive v1 alpha beta)"
V2="$(archive v2 alpha)"

echo "fresh install"
newhome fresh
run "$V1"
check "installs every skill into both dirs" \
  '[ -f "$(C)/alpha/SKILL.md" ] && [ -f "$(C)/beta/SKILL.md" ] && [ -f "$(A)/alpha/SKILL.md" ] && [ -f "$(A)/beta/SKILL.md" ]'
check "copies, not symlinks" '[ ! -L "$(C)/alpha" ]'
check "records ownership" 'owns "$(C)" alpha && owns "$(A)" beta'
check "reports installed" 'grep -q "installed alpha" <<<"$OUT"'

echo "re-run"
run "$V1"
check "reports unchanged" '[ "$(grep -c "unchanged" <<<"$OUT")" -eq 4 ]'

echo "local edit"
echo edited >> "$(C)/alpha/SKILL.md"
run "$V1"
check "reports upgraded" 'grep -q "upgraded  alpha" <<<"$OUT"'
check "restores upstream content" '[ "$(cat "$(C)/alpha/SKILL.md")" = "alpha from v1" ]'

echo "skill removed upstream"
run "$V2"
check "removes it" '[ ! -e "$(C)/beta" ] && [ ! -e "$(A)/beta" ]'
check "drops it from manifest" '! owns "$(C)" beta'
check "reports removed" 'grep -q "removed   beta" <<<"$OUT"'
check "keeps the rest" '[ -f "$(C)/alpha/SKILL.md" ]'

echo "foreign directory"
newhome foreign
mkdir "$(C)/alpha"; echo mine > "$(C)/alpha/SKILL.md"
run "$V1"
check "skips it" 'grep -q "skipped   alpha" <<<"$OUT"'
check "leaves its content" 'grep -qx mine "$(C)/alpha/SKILL.md"'
check "keeps it out of manifest" '! owns "$(C)" alpha'
check "installs it where free" 'grep -qx "alpha from v1" "$(A)/alpha/SKILL.md"'

echo "dev symlink"
newhome symlink
mkdir -p "$WORK/checkout/alpha"; echo dev > "$WORK/checkout/alpha/SKILL.md"
ln -s "$WORK/checkout/alpha" "$(C)/alpha"
run "$V1"
check "replaces it with a copy" '[ ! -L "$(C)/alpha" ] && grep -qx "alpha from v1" "$(C)/alpha/SKILL.md"'
check "leaves the checkout alone" 'grep -qx dev "$WORK/checkout/alpha/SKILL.md"'
check "takes ownership" 'owns "$(C)" alpha'

echo "dev symlink over an owned skill"
newhome owned-symlink
run "$V1"
cp -R "$(C)/alpha" "$WORK/checkout-same"
rm -rf "$(C)/alpha"; ln -s "$WORK/checkout-same" "$(C)/alpha"
run "$V1"
check "replaces it even when content matches" '[ ! -L "$(C)/alpha" ] && grep -q "replaced symlink" <<<"$OUT"'
check "keeps ownership" 'owns "$(C)" alpha'

echo "every skill removed upstream"
newhome empty
EMPTY="$(archive empty)"
run "$V1"
run "$EMPTY"
check "succeeds" '[ "$RC" -eq 0 ]'
check "removes all owned skills" '[ ! -e "$(C)/alpha" ] && [ ! -e "$(A)/beta" ]'
check "installs no literal * skill" '[ ! -e "$(C)/*" ]'

echo "uninstall"
newhome uninstall
mkdir "$(C)/other"
run "$V1"
run "$V1" --uninstall
check "removes owned skills" '[ ! -e "$(C)/alpha" ] && [ ! -e "$(A)/beta" ]'
check "removes manifest" '[ ! -e "$(C)/.jackey8616-skills" ]'
check "leaves foreign dirs" '[ -d "$(C)/other" ]'

echo "bad option"
newhome badopt
run "$V1" --nope
check "rejects it without installing" '[ ! -e "$(C)/alpha" ] && grep -q "unknown option" <<<"$OUT"'

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
