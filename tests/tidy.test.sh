#!/usr/bin/env bash
# Tests for skills/setup-annotation-guard/scripts/tidy.py. Offline, no
# ast-grep: each case commits a file with comments, writes what
# `ast-grep scan -U` leaves behind, and checks what tidy.py makes of it.
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

# expect <name> <file> <before -U> <after -U> <want>
expect() {
  local name="$1" file="$2"
  printf '%s' "$3" > "$WORK/$file"
  git -C "$WORK" add "$file"
  git -C "$WORK" commit -qm "$name"
  printf '%s' "$4" > "$WORK/$file"
  (cd "$WORK" && python3 "$TIDY" "$file" >/dev/null)
  local got
  got="$(cat "$WORK/$file")"
  if [ "$got" = "$5" ]; then
    ok "$name"
  else
    bad "$name" "$(diff <(printf '%s\n' "$5") <(printf '%s\n' "$got"))"
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
const b = 2;'

expect "strips what a trailing comment leaves" b.py \
'x = 1  # trailing
' \
'x = 1
' \
'x = 1'

expect "drops every line of a multi-line doc comment" c.ts \
'const a = 1;

/**
 * doc
 */
function f() {}
' \
'const a = 1;


function f() {}
' \
'const a = 1;

function f() {}'

expect "drops the {} a JSX comment leaves" d.tsx \
'const v = (
  <div>
    {/* note */}
    <span>{}</span>
  </div>
);
' \
'const v = (
  <div>
    {}
    <span>{}</span>
  </div>
);
' \
'const v = (
  <div>
    <span>{}</span>
  </div>
);'

expect "keeps a {} that was there before" e.ts \
'const o = {}; // empty
' \
'const o = {};
' \
'const o = {};'

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
    pass'

expect "joins blank runs around a dropped comment to one" g.ts \
'const a = 1;

// about b

const b = 2;
' \
'const a = 1;



const b = 2;
' \
'const a = 1;

const b = 2;'

expect "removes blank lines left at the top" h.py \
'# header

import os
' \
'

import os
' \
'import os'

expect "leaves lines the removal didn't change" i.py \
'x = 1
# c
y = 2
' \
'x = 1

y = 2
' \
'x = 1
y = 2'

echo "no paths: tidies every changed file"
printf 'a = 1\n# c\nb = 2\n' > "$WORK/j.py"
printf 'c = 3\n' > "$WORK/k.py"
git -C "$WORK" add j.py k.py
git -C "$WORK" commit -qm j
printf 'a = 1\n\nb = 2\n' > "$WORK/j.py"
out="$(cd "$WORK" && python3 "$TIDY")"
[ "$(cat "$WORK/j.py")" = "$(printf 'a = 1\nb = 2')" ] && [ "$out" = "$(printf 'tidied   j.py\n1 file(s) tidied')" ] \
  && ok "finds changed files from git diff" || bad "finds changed files from git diff" "$out"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
