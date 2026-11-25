#!/usr/bin/env bash
# Tests for install.sh. Offline: a fake GitHub on file:// serves the API and
# tarballs, so the real download path runs. Each case installs into a
# throwaway $HOME, piping the script through bash like `curl | bash`.
#
#   bash tests/install.test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

REPO="jackey8616/skills"
GH="$WORK/github"
mkdir -p "$GH/api/repos/$REPO/commits" "$GH/codeload/$REPO/tar.gz"

pass=0
fail=0
ok()   { pass=$((pass + 1)); echo "  ok   $1"; }
bad()  { fail=$((fail + 1)); echo "  FAIL $1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# sha_of <name> — a stable fake 40-char commit sha.
sha_of() { printf '%s' "$1" | shasum | cut -c1-40; }

# tarball <sha> <name> <skill>... — serve a GitHub-shaped tarball at
# codeload/<repo>/tar.gz/<sha>, holding skills/<skill>/SKILL.md.
tarball() {
  local sha="$1" name="$2"; shift 2
  local dir="$WORK/src-$name/skills-$sha"
  mkdir -p "$dir/skills"
  for skill in "$@"; do
    mkdir -p "$dir/skills/$skill"
    echo "$skill from $name" > "$dir/skills/$skill/SKILL.md"
  done
  tar -czf "$GH/codeload/$REPO/tar.gz/$sha" -C "$WORK/src-$name" "skills-$sha"
}

# resolve <ref> <sha> — the API answers <ref> with <sha>.
resolve() { printf '%s' "$2" > "$GH/api/repos/$REPO/commits/$1"; }

# archive <name> <skill>... — publish ref <name> at commit sha_of(<name>).
# Prints the ref.
archive() {
  local name="$1"; shift
  tarball "$(sha_of "$name")" "$name" "$@"
  resolve "$name" "$(sha_of "$name")"
  echo "$name"
}

# run <ref> [args...] — install <ref> into $H against the fake GitHub.
# Output in $OUT, exit code in $RC.
run() {
  local ref="$1"; shift
  RC=0
  OUT="$(HOME="$H" SKILLS_REF="$ref" \
    SKILLS_API="file://$GH/api" SKILLS_CODELOAD="file://$GH/codeload" \
    bash -s -- "$@" < "$ROOT/install.sh" 2>&1)" || RC=$?
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

echo "a skill's tests"
newhome tests
sha="$(sha_of tested)"
dir="$WORK/src-tested/skills-$sha/skills/alpha"
mkdir -p "$dir/tests"
echo "alpha from tested" > "$dir/SKILL.md"
echo "exit 0" > "$dir/tests/alpha.test.sh"
tar -czf "$GH/codeload/$REPO/tar.gz/$sha" -C "$WORK/src-tested" "skills-$sha"
resolve tested "$sha"
run tested
check "leaves tests/ out" '[ -f "$(C)/alpha/SKILL.md" ] && [ ! -e "$(C)/alpha/tests" ] && [ ! -e "$(A)/alpha/tests" ]'
run tested
check "reports unchanged on re-run" '[ "$(grep -c "unchanged alpha" <<<"$OUT")" -eq 2 ]'

echo "uninstall"
newhome uninstall
mkdir "$(C)/other"
run "$V1"
run "$V1" --uninstall
check "removes owned skills" '[ ! -e "$(C)/alpha" ] && [ ! -e "$(A)/beta" ]'
check "removes manifest" '[ ! -e "$(C)/.jackey8616-skills" ]'
check "leaves foreign dirs" '[ -d "$(C)/other" ]'

echo "ref resolution"
newhome ref
PIN_SHA="$(sha_of pinned)"
archive pinned alpha >/dev/null
run pinned
check "downloads by the resolved commit, not the ref" \
  '[ "$RC" -eq 0 ] && [ ! -e "$GH/codeload/$REPO/tar.gz/pinned" ] && [ -f "$(C)/alpha/SKILL.md" ]'
check "reports the short commit" 'grep -q "@ ${PIN_SHA:0:7} " <<<"$OUT"'
check "records the full commit in the manifest" 'grep -qx "# $REPO @ $PIN_SHA" "$(C)/.jackey8616-skills"'

echo "default ref"
newhome default
archive main beta >/dev/null
run ""
check "installs main when SKILLS_REF is unset" \
  '[ "$RC" -eq 0 ] && [ "$(cat "$(C)/beta/SKILL.md")" = "beta from main" ]'

echo "API unreachable"
newhome noapi
tarball v9 v9 alpha
run v9
check "falls back to downloading by the ref" \
  '[ "$RC" -eq 0 ] && [ "$(cat "$(C)/alpha/SKILL.md")" = "alpha from v9" ]'
check "reports the ref" 'grep -q "@ v9 " <<<"$OUT"'

echo "unknown ref"
newhome unknown
run "$V1"
run nope
check "fails" '[ "$RC" -ne 0 ] && grep -q "could not download $REPO@nope" <<<"$OUT"'
check "leaves the existing install alone" \
  '[ -f "$(C)/alpha/SKILL.md" ] && owns "$(C)" alpha && grep -qx "# $REPO @ $(sha_of v1)" "$(C)/.jackey8616-skills"'

echo "bad option"
newhome badopt
run "$V1" --nope
check "rejects it without installing" '[ ! -e "$(C)/alpha" ] && grep -q "unknown option" <<<"$OUT"'

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
