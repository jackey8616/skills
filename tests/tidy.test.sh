#!/usr/bin/env bash
# Tests for skills/setup-annotation-guard/scripts/tidy.py. Offline, no
# ast-grep: each case commits a file, removes the given comments the way
# `ast-grep scan -U` does, writes the cuts file that scan's --json=stream
# would have printed, and checks what tidy.py makes of it.
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

# remove <file> <out-prefix> <removal>... — delete each removal from <file>
# in order, as -U would, and write one cuts file per pass. A removal is
# `rule::text`, or just `text` for rule no-comments-x; `||` starts a new pass.
# The language is the one ast-grep gives the file's extension.
remove() {
  python3 - "$@" <<'EOF'
import json, sys
path, prefix, *specs = sys.argv[1:]
language = {"ts": "TypeScript", "tsx": "Tsx", "js": "JavaScript", "py": "Python", "c": "C", "sh": "Bash",
            "css": "Css", "html": "Html", "go": "Go"}[path.rsplit(".", 1)[-1]]
passes, current = [], []
for spec in specs:
    if spec == "||":
        passes.append(current)
        current = []
    else:
        current.append(spec)
passes.append(current)
text = open(path, "rb").read()
for n, specs in enumerate(passes):
    rows, pos = [], 0
    for spec in specs:
        rule, _, needle = spec.rpartition("::")
        needle = needle.replace("·", " ").encode()
        start = text.index(needle, pos)
        rows.append((start, start + len(needle), rule or "no-comments-x"))
        pos = start + len(needle)
    with open(f"{prefix}.{n}.jsonl", "w") as f:
        for start, end, rule in rows:
            f.write(json.dumps({"file": path, "ruleId": rule, "replacement": "", "text": text[start:end].decode(), "language": language,
                                "replacementOffsets": {"start": start, "end": end}}) + "\n")
    for start, end, _ in reversed(rows):
        text = text[:start] + text[end:]
print(len(passes))
open(path, "wb").write(text)
EOF
}

# cuts_args <prefix> <n> — the cuts files for n passes, in order.
cuts_args() { local i; for ((i = 0; i < $2; i++)); do printf -- '%s\0' "$1.$i.jsonl"; done; }

# expect <name> <file> <before> <want> <removal>... — passes only if tidy.py
# exits 0 and its output matches <want> byte for byte.
expect() {
  local name="$1" file="$2" before="$3" want="$4" rc=0 n
  shift 4
  dots "$before" > "$WORK/$file"
  git -C "$WORK" add "$file"
  git -C "$WORK" commit -qm "$name"
  n="$(cd "$WORK" && remove "$file" "cuts-$file" "$@")"
  (cd "$WORK" && cuts_args "cuts-$file" "$n" | xargs -0 python3 "$TIDY" --base HEAD >/dev/null 2>&1) || rc=$?
  if [ "$rc" -ne 0 ]; then
    bad "$name" "tidy.py exited $rc"
  elif cmp -s "$WORK/$file" <(dots "$want"); then
    ok "$name"
  else
    bad "$name" "$(diff <(dots "$want" | od -c) <(od -c < "$WORK/$file"))"
  fi
}

expect "drops a full-line comment's line" a.ts \
'const a = 1;
// full line
const b = 2;
' \
'const a = 1;
const b = 2;
' '// full line'

expect "strips the spaces a trailing comment leaves" b.py \
'x = 1  # trailing
' \
'x = 1
' '# trailing'

expect "drops every line of a multi-line doc comment" c.ts \
'const a = 1;

/**
 * doc
 */
function f() {}
' \
'const a = 1;

function f() {}
' '/**
 * doc
 */'

expect "caps merged blank runs at the longer one" f.py \
'import os


# section
def f():
    pass
' \
'import os


def f():
    pass
' '# section'

expect "joins blank runs around a dropped comment to one" g.ts \
'const a = 1;

// about b

const b = 2;
' \
'const a = 1;

const b = 2;
' '// about b'

expect "removes blank lines left at the top" h.py \
'# header

import os
' \
'import os
' '# header'

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
' '# c'

expect "keeps CRLF line endings" j.py \
"$(printf 'x = 1\r\n# c\r\ny = 2\r\n')" \
"$(printf 'x = 1\r\ny = 2\r\n')" '# c'

expect "keeps trailing spaces that are string data" l.js \
'// full line
const s = /* remove */ `a···
b`;
' \
'const s =  `a···
b`;
' '// full line' '/* remove */'

expect "keeps string data a nearby removal repeats" n.js \
'/*
·`;

`
*/x = `a··
·`;
' \
'x = `a··
·`;
' '/*
·`;

`
*/'

expect "puts a space back where a comment separated two tokens" o.js \
'return/* x */1;
foo(/* a */1);
a -/* b */-c;
' \
'return 1;
foo(1);
a - -c;
' '/* x */' '/* a */' '/* b */'

expect "puts a line break back where a comment held one" s.js \
'function f() { return/*
comment
*/1; }
  x = 1; /* a
  b */ y = 2;
' \
'function f() { return
1; }
  x = 1;
  y = 2;
' '/*
comment
*/' '/* a
  b */'

expect "puts a space back before punctuation that would join" t.c \
'#define F/**/(x)
int a = 1/* x */.5;
#define VALUE (1 /* x
y */ + 2)/* z
*/int b;
' \
'#define F (x)
int a = 1 .5;
#define VALUE (1  + 2) int b;
' '/**/' '/* x */' '/* x
y */' '/* z
*/'

expect "in CSS, puts a space back only between two names" v.css \
'a/* x */:hover { color: red; }
@media/* y */screen { a { color: red; } }
' \
'a:hover { color: red; }
@media screen { a { color: red; } }
' '/* x */' '/* y */'

expect "splits lines at LF only, so a U+2028 isn't stripped as trailing space" x.js \
"$(printf 'a = 1 /* d */\xe2\x80\xa8b = 2\nconst s = "a\xe2\x80\xa8b  "; // c\n')" \
"$(printf 'a = 1 \xe2\x80\xa8b = 2\nconst s = "a\xe2\x80\xa8b  ";\n')" '/* d */' '// c'

expect "counts every JavaScript line terminator as a line break" w.js \
"$(printf 'function f() { return/*\r*/1; }\nfunction g() { return/*\xe2\x80\xa8*/1; }\n')" \
"$(printf 'function f() { return\n1; }\nfunction g() { return\n1; }\n')" \
"$(printf '/*\r*/')" "$(printf '/*\xe2\x80\xa8*/')"

expect "leaves HTML whitespace as -U made it" u.html \
'<pre>a  <!-- note -->
b</pre>
' \
'<pre>a··
b</pre>
' 'no-comments-html::<!-- note -->'

expect "joins text an HTML comment split" p.html \
'<p>a<!-- x -->b</p>
' \
'<p>ab</p>
' 'no-comments-html::<!-- x -->'

expect "follows a cut through a second pass (empty JSX)" q.tsx \
'const e = <b>a{/* x */}b</b>;
' \
'const e = <b>ab</b>;
' 'no-comments-tsx::/* x */' '||' 'empty-jsx::{}'

echo "files: from the cuts, spaces in names included"
printf 'a = 1\n# c\nb = 2\n' > "$WORK/my file.py"
printf 'c = 3\n' > "$WORK/k.py"
git -C "$WORK" add "my file.py" k.py
git -C "$WORK" commit -qm spaces
(cd "$WORK" && remove "my file.py" cuts-space '# c' >/dev/null)
rc=0
out="$(cd "$WORK" && python3 "$TIDY" --base HEAD cuts-space.0.jsonl 2>&1)" || rc=$?
if [ "$rc" -eq 0 ] && [ "$(cat "$WORK/my file.py")" = "$(printf 'a = 1\nb = 2')" ] \
  && [ "$out" = "$(printf 'tidied   my file.py\n1 file(s) tidied')" ]; then
  ok "tidies the files the cuts name"
else
  bad "tidies the files the cuts name" "exit $rc: $out"
fi

echo "--base: edits before the snapshot are left alone"
printf 'Fact.\n' > "$WORK/README.md"
printf 'x = 1  # c\n' > "$WORK/m.py"
git -C "$WORK" add README.md m.py
git -C "$WORK" commit -qm base
printf 'Updated fact.  \nNext line.\n' > "$WORK/README.md"
snap="$(git -C "$WORK" stash create)"
(cd "$WORK" && remove m.py cuts-m '# c' >/dev/null)
rc=0
(cd "$WORK" && python3 "$TIDY" --base "$snap" cuts-m.0.jsonl >/dev/null 2>&1) || rc=$?
if [ "$rc" -eq 0 ] && [ "$(cat "$WORK/README.md")" = "$(printf 'Updated fact.  \nNext line.')" ] \
  && [ "$(cat "$WORK/m.py")" = "x = 1" ]; then
  ok "tidies the removal, keeps the earlier hard line break"
else
  bad "tidies the removal, keeps the earlier hard line break" "exit $rc: $(od -c < "$WORK/README.md" | head -2)"
fi

expect "Go: only an LF in a comment is a line break" y.go \
"$(printf 'func f() int { return/*\r*/1 }\nfunc g() int { return/*\n*/1 }\n')" \
"$(printf 'func f() int { return 1 }\nfunc g() int { return\n1 }\n')" \
"$(printf '/*\r*/')" "$(printf '/*\n*/')"

expect "keeps the empty line that ends a line continuation" aa.sh \
'echo start \
# explanation
echo next
' \
'echo start \

echo next
' '# explanation'

echo "a removal that leaves a line continuation is named"
printf '#define UNUSED \\/* note */\nint x = 1;\n#define OK \\\n  1 /* c */\n' > "$WORK/z.c"
git -C "$WORK" add z.c
git -C "$WORK" commit -qm z
(cd "$WORK" && remove z.c cuts-z '/* note */' '/* c */' >/dev/null)
rc=0
out="$(cd "$WORK" && python3 "$TIDY" --base HEAD cuts-z.0.jsonl 2>&1)" || rc=$?
if [ "$rc" -eq 3 ] && echo "$out" | grep -q '^check    z.c:1 ' && ! echo "$out" | grep -q 'z.c:[34] '; then
  ok "exit 3, the new continuation named, an existing one left alone"
else
  bad "names a new line continuation" "exit $rc: $out"
fi

echo "a file the cuts don't explain is skipped"
printf 'x = 1  # c\ny = 2\n' > "$WORK/r.py"
git -C "$WORK" add r.py
git -C "$WORK" commit -qm r
(cd "$WORK" && remove r.py cuts-r '# c' >/dev/null)
printf 'x = 1  \ny = 3\n' > "$WORK/r.py"
rc=0
out="$(cd "$WORK" && python3 "$TIDY" --base HEAD cuts-r.0.jsonl 2>&1)" || rc=$?
if [ "$rc" -eq 0 ] && [ "$(cat "$WORK/r.py")" = "$(printf 'x = 1  \ny = 3')" ] && echo "$out" | grep -q '^skipped  r.py'; then
  ok "left untouched and reported"
else
  bad "skips an unexplained file" "exit $rc: $out"
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
