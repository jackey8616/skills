#!/usr/bin/env bash
# Tests for skills/setup-annotation-guard/scripts/tidy.py. Offline, no
# ast-grep: each case commits a file with comments, writes what
# `ast-grep scan -U` leaves behind, and checks what tidy.py makes of it.
# In the fixtures, · stands for a space, so trailing spaces stay visible.
#
#   bash tests/tidy.test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TIDY="$ROOT/skills/setup-annotation-guard/scripts/tidy.py"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0
ok()   { pass=$((pass + 1)); echo "  ok   $1"; }
bad()  { fail=$((fail + 1)); echo "  FAIL $1"; echo "$2" | sed 's/^/       /'; }

git -C "$WORK" init -q
git -C "$WORK" config user.name test
git -C "$WORK" config user.email test@example.com
git -C "$WORK" config core.autocrlf false

dots() { printf '%s' "$1" | sed 's/·/ /g'; }

# expect <name> <file> <before -U> <after -U> <want> — passes only if tidy.py
# exits 0, the input really differs from what's wanted, and the output
# matches byte for byte.
expect() {
  local name="$1" file="$2" rc=0
  dots "$3" > "$WORK/$file"
  git -C "$WORK" add "$file"
  git -C "$WORK" commit -qm "$name"
  dots "$4" > "$WORK/$file"
  if cmp -s "$WORK/$file" <(dots "$5"); then
    bad "$name" "fixture already equals the expected output"
    return
  fi
  (cd "$WORK" && python3 "$TIDY" "$file" >/dev/null 2>&1) || rc=$?
  if [ "$rc" -ne 0 ]; then
    bad "$name" "tidy.py exited $rc"
  elif cmp -s "$WORK/$file" <(dots "$5"); then
    ok "$name"
  else
    bad "$name" "$(diff <(dots "$5" | od -c) <(od -c < "$WORK/$file"))"
  fi
}

expect "drops a full-line comment's line" a.ts \
'const a = 1;
// full line
const b = 2;
' \
'const a = 1;

const b = 2;
' \
'const a = 1;
const b = 2;
'

expect "strips the spaces a trailing comment leaves" b.py \
'x = 1  # trailing
' \
'x = 1··
' \
'x = 1
'

expect "drops every line of a multi-line doc comment" c.ts \
'const a = 1;

/**
 * doc
 */
function f() {}
' \
'const a = 1;

·
function f() {}
' \
'const a = 1;

function f() {}
'

expect "caps merged blank runs at the longer one" f.py \
'import os


# section
def f():
    pass
' \
'import os




def f():
    pass
' \
'import os


def f():
    pass
'

expect "joins blank runs around a dropped comment to one" g.ts \
'const a = 1;

// about b

const b = 2;
' \
'const a = 1;



const b = 2;
' \
'const a = 1;

const b = 2;
'

expect "removes blank lines left at the top" h.py \
'# header

import os
' \
'

import os
' \
'import os
'

expect "keeps unchanged trailing spaces and whitespace-only lines" i.py \
'x = 1···
s = """a
···
b"""
# c
y = 2
' \
'x = 1···
s = """a
···
b"""

y = 2
' \
'x = 1···
s = """a
···
b"""
y = 2
'

expect "keeps CRLF line endings" j.py \
"$(printf 'x = 1\r\n# c\r\ny = 2\r\n')" \
"$(printf 'x = 1\r\n\r\ny = 2\r\n')" \
"$(printf 'x = 1\r\ny = 2\r\n')"

expect "keeps trailing spaces that are string data" l.js \
'// full line
const s = /* remove */ `a···
b`;
' \
'
const s =  `a···
b`;
' \
'const s =  `a···
b`;
'

echo "no paths: tidies every changed file"
printf 'a = 1\n# c\nb = 2\n' > "$WORK/my file.py"
printf 'c = 3\n' > "$WORK/k.py"
git -C "$WORK" add "my file.py" k.py
git -C "$WORK" commit -qm spaces
printf 'a = 1\n\nb = 2\n' > "$WORK/my file.py"
rc=0
out="$(cd "$WORK" && python3 "$TIDY" 2>&1)" || rc=$?
if [ "$rc" -eq 0 ] && [ "$(cat "$WORK/my file.py")" = "$(printf 'a = 1\nb = 2')" ] \
  && [ "$out" = "$(printf 'tidied   my file.py\n1 file(s) tidied')" ]; then
  ok "finds changed files from git diff, spaces in names included"
else
  bad "finds changed files from git diff, spaces in names included" "exit $rc: $out"
fi

echo "--base: edits before the snapshot are left alone"
printf 'Fact.\n' > "$WORK/README.md"
printf 'x = 1  # c\n' > "$WORK/m.py"
git -C "$WORK" add README.md m.py
git -C "$WORK" commit -qm base
printf 'Updated fact.  \nNext line.\n' > "$WORK/README.md"
snap="$(git -C "$WORK" stash create)"
printf 'x = 1  \n' > "$WORK/m.py"
rc=0
(cd "$WORK" && python3 "$TIDY" --base "$snap" >/dev/null 2>&1) || rc=$?
if [ "$rc" -eq 0 ] && [ "$(cat "$WORK/README.md")" = "$(printf 'Updated fact.  \nNext line.')" ] \
  && [ "$(cat "$WORK/m.py")" = "x = 1" ]; then
  ok "tidies the removal, keeps the earlier hard line break"
else
  bad "tidies the removal, keeps the earlier hard line break" "exit $rc: $(od -c < "$WORK/README.md" | head -2)"
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
