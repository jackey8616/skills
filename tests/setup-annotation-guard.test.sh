#!/usr/bin/env bash
# Tests for the ast-grep claims in skills/setup-annotation-guard/SKILL.md.
# Offline, but needs an ast-grep binary: on PATH, or named by $AST_GREP.
# The comment-kinds table, the docstring rule, the lint command, and the
# command lines for scripts/ledger.sh, remove.sh, and checks.sh are read from
# SKILL.md itself, so the skill and these tests can't drift apart.
#
#   bash tests/setup-annotation-guard.test.sh
#   AST_GREP=/path/to/ast-grep bash tests/setup-annotation-guard.test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$ROOT/skills/setup-annotation-guard/SKILL.md"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0
ok()   { pass=$((pass + 1)); echo "  ok   $1"; }
bad()  { fail=$((fail + 1)); echo "  FAIL $1 — got: $2"; }

# The skill runs ast-grep by that name, so put whichever binary we have on
# PATH as `ast-grep`.
sg_bin="$(command -v "${AST_GREP:-ast-grep}" || true)"
if [ -z "$sg_bin" ]; then
  echo "ast-grep not found. Install it, or set AST_GREP to its path." >&2
  exit 1
fi
mkdir -p "$WORK/bin"
ln -s "$sg_bin" "$WORK/bin/ast-grep"
export PATH="$WORK/bin:$PATH"
echo "ast-grep $(ast-grep --version | awk '{print $2}')"

# skill_cmd <script> <scratchpad> — SKILL.md's command line for one of its
# scripts, with the placeholders filled in.
skill_cmd() {
  grep -m1 "scripts/$1\"" "$SKILL" | sed -e 's/^ *//' -e "s|<scratchpad>|$2|g" \
    -e "s|\${CLAUDE_SKILL_DIR}|$ROOT/skills/setup-annotation-guard|g"
}

# count <lang> <file> <rule> — number of matches of an inline rule.
count() {
  ast-grep scan --inline-rules "{id: t, language: $1, rule: $3}" --json=stream "$2" 2>/dev/null | wc -l | tr -d ' '
}

# One sample per language, each with a known number of comments, plus a
# string holding comment characters that must not count.
sample() {
  case "$1" in
    TypeScript) echo "ts|2|// a
/* b */
const s = \"// no\";" ;;
    Tsx) echo "tsx|2|// a
/* b */
const s = \"// no\";" ;;
    JavaScript) echo "js|2|// a
/* b */
const s = \"// no\";" ;;
    Go) echo "go|2|// a
/* b */
package p" ;;
    Python) echo "py|2|# a
s = \"# no\"  # b" ;;
    Bash) echo "sh|2|# a
echo \"#no\"  # b" ;;
    Ruby) echo "rb|2|# a
s = \"# no\" # b" ;;
    C) echo "c|2|// a
/* b */
char *s = \"// no\";" ;;
    C++) echo "cpp|2|// a
/* b */
const char *s = \"// no\";" ;;
    CSS) echo "css|1|/* a */
p::before { content: \"/* no */\"; }" ;;
    HTML) echo "html|1|<!-- a -->
<p>&lt;!-- no --&gt;</p>" ;;
    YAML) echo "yaml|2|# a
k: \"# no\" # b" ;;
    Rust) echo "rs|3|// a
/* b */
/// c
fn f() { let _s = \"// no\"; }" ;;
    Java) echo "java|2|// a
/* b */
class A { String s = \"// no\"; }" ;;
    Kotlin) echo "kt|2|// a
/* b */
val s = \"// no\"" ;;
    *) return 1 ;;
  esac
}

# ast-grep's name for a language where the table uses the common one.
sg_lang() { [ "$1" = "C++" ] && echo cpp || echo "$1"; }

echo "comment kinds table"
table="$(awk '/^\| Language \| Comment kinds \|/{f=1; next} f && /^\|/{print; next} f{exit}' "$SKILL" | tail -n +2)"
[ -n "$table" ] || bad "table found in SKILL.md" "nothing"
while IFS= read -r row; do
  langs="$(echo "$row" | awk -F'|' '{print $2}')"
  kinds="$(echo "$row" | awk -F'|' '{print $3}' | grep -oE '`[a-z_]+`' | tr -d '`' | awk '!seen[$0]++')"
  rule="{any: [$(echo "$kinds" | sed 's/.*/{kind: &}/' | paste -sd, -)]}"
  IFS=',' read -ra list <<< "$langs"
  for lang in "${list[@]}"; do
    lang="$(echo "$lang" | xargs)"
    if ! s="$(sample "$lang")"; then
      bad "$lang has a sample" "none in this test"
      continue
    fi
    ext="${s%%|*}"; rest="${s#*|}"; want="${rest%%|*}"; code="${rest#*|}"
    printf '%s\n' "$code" > "$WORK/sample.$ext"
    got="$(count "$(sg_lang "$lang")" "$WORK/sample.$ext" "$rule")"
    [ "$got" = "$want" ] && ok "$lang: $want comments as $(echo $kinds | tr ' ' /)" \
      || bad "$lang: $want comments as $(echo $kinds | tr ' ' /)" "$got"
  done
done <<< "$table"

echo "position-bound exceptions"
pos="$(awk '/^Position-bound exceptions/{f=1} f && /^```yaml/{g=1; next} g && /^```/{exit} g' "$SKILL")"
[ -n "$pos" ] || bad "position-bound exceptions found in SKILL.md" "nothing"
printf 'id: p\nlanguage: Python\nseverity: error\nmessage: m\nrule:\n  kind: comment\n  not:\n    any:\n%s\n' \
  "$(printf '%s\n' "$pos" | sed 's/^/      /')" > "$WORK/pos.yml"
# pos_case <name> <want: start lines of matches> <file contents>
pos_case() {
  printf '%s\n' "$3" > "$WORK/pos.py"
  local got
  got="$(ast-grep scan -r "$WORK/pos.yml" --json=stream "$WORK/pos.py" 2>/dev/null \
    | awk 'match($0, /"start":\{"line":[0-9]+/) { print substr($0, RSTART + 16, RLENGTH - 16) }' | sort -n | paste -sd' ' -)"
  [ "$got" = "$2" ] && ok "$1" || bad "$1" "matches on lines '$got'"
}
pos_case "allows a shebang, then a coding line, at the top" "" '#!/usr/bin/env python3
# -*- coding: utf-8 -*-
x = 1'
pos_case "allows a coding line alone at the top" "" '# -*- coding: utf-8 -*-
x = 1'
pos_case "flags #! and coding lines after code, and inside a body" "1 2 4 5" 'x = 1
#! free comment
# -*- coding: utf-8 -*-
def f():
    #! in a body
    # -*- coding: latin-1 -*-
    return 1'
pos_case "flags a coding line after an ordinary comment" "1 2" '#!/bin/bash -e
# a
# -*- coding: utf-8 -*-'
pos_case "allows each listed shebang" "" '#!/bin/bash -e
x = 1'
pos_case "flags an unlisted shebang" "0" '#!/usr/bin/env -S python3 -u
x = 1'
pos_case "flags prose in the shebang or encoding slot" "2 3" '

#!/usr/bin/env do-not-refactor-this-function
# -*- coding: do-not-refactor-this-function -*-
x = 1'
pos_case "flags prose after #!, even after blank lines or indentation" "2 3" '

#! arbitrary prose
   #! more prose
x = 1'
pos_case "flags prose dressed as an env shebang" "0" '#!/usr/bin/env this is prose
x = 1'

echo "typescript reference exceptions"
ref="$(awk '/^TypeScript `\/\/\/ <reference>` lines at the top/{f=1} f && /^```yaml/{g=1; next} g && /^```/{exit} g' "$SKILL")"
[ -n "$ref" ] || bad "reference exceptions found in SKILL.md" "nothing"
printf 'id: r\nlanguage: TypeScript\nseverity: error\nmessage: m\nrule:\n  kind: comment\n  not:\n    any:\n%s\n' \
  "$(printf '%s\n' "$ref" | sed 's/^/      /')" > "$WORK/ref.yml"
# ref_case <name> <want: start lines of matches> <file contents>
ref_case() {
  printf '%s\n' "$3" > "$WORK/ref.ts"
  local got
  got="$(ast-grep scan -r "$WORK/ref.yml" --json=stream "$WORK/ref.ts" 2>/dev/null \
    | awk 'match($0, /"start":\{"line":[0-9]+/) { print substr($0, RSTART + 16, RLENGTH - 16) }' | sort -n | paste -sd' ' -)"
  [ "$got" = "$2" ] && ok "$1" || bad "$1" "matches on lines '$got'"
}
ref_case "allows listed references in a row at the top" "" '/// <reference types="vite/client" />
/// <reference types="vite-plugin-pwa/client" />
const a = 1;'
ref_case "flags a listed reference after code" "2" '/// <reference types="vite/client" />
const a = 1;
/// <reference types="vite/client" />'
ref_case "flags an unlisted reference at the top" "0" '/// <reference types="other" />
const a = 1;'

echo "HTML text elements"
html_text="$(awk '/^The HTML rule always has one exception/{f=1} f && /^```yaml/{g=1; next} g && /^```/{exit} g' "$SKILL")"
[ -n "$html_text" ] || bad "HTML text-element exception found in SKILL.md" "nothing"
printf 'id: t\nlanguage: Html\nrule:\n  kind: comment\n  not:\n    any:\n%s\n' "$html_text" > "$WORK/html.yml"
printf '<title>a<!-- t -->b</title>\n<TextArea>x<!-- ta --></TextArea>\n<xmp><!-- x --></xmp>\n<noscript><!-- n --></noscript>\n<pre><!-- p --></pre>\n<div><p><!-- ok --></p></div>\n<svg><title><!-- svg -->Icon</title></svg>\n' > "$WORK/text.html"
got="$(ast-grep scan -r "$WORK/html.yml" --json=stream "$WORK/text.html" 2>/dev/null | python3 -c 'import json, sys; print(" ".join(json.loads(l)["text"] for l in sys.stdin))')"
[ "$got" = "<!-- p --> <!-- ok --> <!-- svg -->" ] && ok "<!-- --> in title, textarea, xmp, noscript is text, left alone; in pre, p, and an SVG title a comment" \
  || bad "HTML text elements" "$got"

echo "removal pairs and tidy, end to end"
# run_removal <repo> — SKILL.md's remove.sh command, run in <repo>.
run_removal() {
  mkdir -p "$WORK/cuts"
  (cd "$1" && bash -c "$(skill_cmd remove.sh "$WORK/cuts")")
}
[ -n "$(skill_cmd remove.sh x)" ] || bad "remove.sh command found in SKILL.md" "nothing"
jsx="$WORK/jsx"
mkdir -p "$jsx/fixtures" "$jsx/rules"
git -C "$jsx" init -q
printf 'ruleDirs: [rules]\n' > "$jsx/sgconfig.yml"
for l in Tsx Html JavaScript Css; do
  id="no-comments-$(echo "$l" | tr 'A-Z' 'a-z')"
  printf 'id: %s\nlanguage: %s\nseverity: error\nignores: ["fixtures/**"]\nrule: { kind: comment }\nfix: ""\n' "$id" "$l" > "$jsx/rules/$id.yml"
done
# A rule the repo already had: the cleanup must not apply its fix.
printf 'id: prefer-two\nlanguage: Tsx\nseverity: error\nrule: { pattern: "const q = 1" }\nfix: "const q = 2"\n' > "$jsx/rules/prefer-two.yml"
printf 'const o = {/* x */};\nfunction f() {/* y */}\nconst v = <div>{/* a */}<span>{x}</span>{\n  /* b */\n}</div>;\nfunction g() { return 1; } // r\n// full line\nconst s = `a  \n`;\nconst q = 1;\n' > "$jsx/a.tsx"
printf '<!-- h -->\n<style>\n/* c */\na:hover {}\n</style>\n<script>\n// d\nf();\n</script>\n' > "$jsx/b.html"
printf 'const v = <div>{}</div>;\n' > "$jsx/fixtures/page.tsx"
git -C "$jsx" add -A
git -C "$jsx" -c user.name=t -c user.email=t@t commit -qm init
rc=0; run_removal "$jsx" >/dev/null 2>"$WORK/tidy.err" || rc=$?
[ "$rc" -eq 0 ] && ok "tidy.py exits 0" || bad "tidy.py exits 0" "exit $rc: $(cat "$WORK/tidy.err")"
[ ! -s "$WORK/tidy.err" ] && ok "prints no ast-grep messages when nothing failed" || bad "quiet on success" "$(head -3 "$WORK/tidy.err")"
got="$(cat "$jsx/a.tsx")"
want="$(printf 'const o = {};\nfunction f() {}\nconst v = <div><span>{x}</span></div>;\nfunction g() { return 1; }\nconst s = `a  \n`;\nconst q = 1;')"
[ "$got" = "$want" ] \
  && ok "removes comments and empty JSX, keeps objects, blocks, string data; no other rule's fix" \
  || bad "end to end" "$(diff <(echo "$want") <(echo "$got"))"
got="$(cat "$jsx/b.html")"
want="$(printf '<style>\na:hover {}\n</style>\n<script>\nf();\n</script>')"
[ "$got" = "$want" ] && ok "removes HTML, CSS, and JavaScript comments from one HTML file" \
  || bad "mixed-language HTML" "$(diff <(echo "$want") <(echo "$got"))"
[ "$(cat "$jsx/fixtures/page.tsx")" = 'const v = <div>{}</div>;' ] \
  && ok "leaves files the comment removal didn't change" || bad "unchanged files left alone" "$(cat "$jsx/fixtures/page.tsx")"

snapf="$(cat "$WORK/cuts/snap" 2>/dev/null)"
[ -n "$snapf" ] && git -C "$jsx" cat-file -e "$snapf^{commit}" 2>/dev/null \
  && ok "records the snapshot sha in <scratchpad>/snap" || bad "snapshot recorded" "$snapf"
printf 'id: no-comments-bad\nlanguage: Nope\nrule: { kind: comment }\n' > "$jsx/rules/no-comments-bad.yml"
rc=0; run_removal "$jsx" >/dev/null 2>&1 || rc=$?
err="$(run_removal "$jsx" 2>&1 >/dev/null)"
[ "$rc" = 2 ] && echo "$err" | grep -q 'exited' && ok "exits 2 when ast-grep fails, and shows why" || bad "ast-grep failure" "exit $rc: $err"
rm "$jsx/rules/no-comments-bad.yml"
git -C "$jsx" checkout -q -- . && rm -f "$WORK/cuts/snap" && mkdir "$WORK/cuts/snap"
before="$(git -C "$jsx" diff HEAD)"
rc=0; run_removal "$jsx" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] && [ "$(git -C "$jsx" diff HEAD)" = "$before" ] && ok "stops before removing anything when the snapshot can't be saved" \
  || bad "snapshot write failure" "exit $rc"
rmdir "$WORK/cuts/snap"
if command -v zsh >/dev/null; then
  printf 'const z = 1; // z\n' > "$jsx/z.tsx"
  git -C "$jsx" add z.tsx
  git -C "$jsx" -c user.name=t -c user.email=t@t commit -qm z
  rc=0; (cd "$jsx" && zsh -c "$(skill_cmd remove.sh "$WORK/cuts")" >/dev/null 2>&1) || rc=$?
  [ "$rc" = 0 ] && [ "$(cat "$jsx/z.tsx")" = "const z = 1;" ] && ok "runs the same from zsh" || bad "remove.sh from zsh" "exit $rc"
fi

cpp="$WORK/cpp"
mkdir -p "$cpp/rules"
git -C "$cpp" init -q
printf 'ruleDirs: [rules]\n' > "$cpp/sgconfig.yml"
printf 'id: no-comments-c\nlanguage: C\nseverity: error\nrule: { kind: comment }\nfix: ""\n' > "$cpp/rules/no-comments-c.yml"
printf 'id: no-comments-c++\nlanguage: C++\nseverity: error\nrule: { kind: comment }\nfix: ""\n' > "$cpp/rules/no-comments-c++.yml"
printf 'int a; // c\n' > "$cpp/a.c"
printf 'int b; // cpp\n' > "$cpp/b.cpp"
git -C "$cpp" add -A
git -C "$cpp" -c user.name=t -c user.email=t@t commit -qm init
rc=0; run_removal "$cpp" >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] && [ "$(cat "$cpp/a.c")" = "int a;" ] && [ "$(cat "$cpp/b.cpp")" = "int b;" ] \
  && ok "a rule id with regex characters (no-comments-c++) selects only its own rule" || bad "c++ rule id" "exit $rc: $(cat "$cpp/b.cpp")"

sub="$WORK/sub"
mkdir -p "$sub/inner" "$sub/outer/rules"
git -C "$sub/inner" init -q
printf 'x = 1  # inner\n' > "$sub/inner/i.py"
git -C "$sub/inner" add -A
git -C "$sub/inner" -c user.name=t -c user.email=t@t commit -qm i
git -C "$sub/outer" init -q
printf 'ruleDirs: [rules]\n' > "$sub/outer/sgconfig.yml"
printf 'id: no-comments-python\nlanguage: Python\nseverity: error\nrule: { kind: comment }\nfix: ""\n' > "$sub/outer/rules/no-comments-python.yml"
printf 'y = 2  # outer\n' > "$sub/outer/o.py"
git -C "$sub/outer" -c protocol.file.allow=always submodule -q add "$sub/inner" lib >/dev/null 2>&1
git -C "$sub/outer" add -A
git -C "$sub/outer" -c user.name=t -c user.email=t@t commit -qm o
rc=0; err="$(run_removal "$sub/outer" 2>&1 >/dev/null)" || rc=$?
[ "$rc" = 2 ] && echo "$err" | grep -q 'submodule lib' && [ -z "$(git -C "$sub/outer" status --porcelain)" ] \
  && ok "stops, before removing anything, when a rule reaches a submodule" || bad "submodule reached" "exit $rc: $err"
printf 'ignores: ["lib/**"]\n' >> "$sub/outer/rules/no-comments-python.yml"
rc=0; run_removal "$sub/outer" >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] && [ "$(cat "$sub/outer/o.py")" = "y = 2" ] && [ "$(cat "$sub/outer/lib/i.py")" = "x = 1  # inner" ] \
  && ok "with the submodule in ignores, removes only the repo's own comments" || bad "submodule ignored" "exit $rc: $(cat "$sub/outer/o.py"; cat "$sub/outer/lib/i.py")"

echo "checks.sh"
chk="$WORK/chk"
mkdir -p "$chk"
printf 'build: printf "%%s\\n" a b\ntypecheck: absent\n\nlint: false\ntest: echo "3 passed"; exit 0' > "$chk/checks.txt"
for shell in bash zsh; do
  command -v "$shell" >/dev/null || continue
  rm -rf "$chk/out"
  got="$(cd "$chk" && "$shell" -c "$(skill_cmd checks.sh "$chk" | sed -e "s|git rev-parse HEAD > $chk/base && ||" -e "s|$chk/before|$chk/out|")")"
  want="$(printf 'build  exit 0\ntypecheck  absent\nlint  exit 1\ntest  exit 0')"
  [ "$got" = "$want" ] && [ "$(cat "$chk/out/status.txt")" = "$want" ] && [ "$(cat "$chk/out/build.log")" = "$(printf 'a\nb')" ] && [ "$(cat "$chk/out/test.log")" = "3 passed" ] \
    && ok "$shell: every check run with bash, absent ones named, status and output recorded" \
    || bad "checks.sh from $shell" "$got"
done

bad_grep="$(grep -n "git grep" "$SKILL" | grep 'ast-grep\[-\]ignore' | grep -v -- ' -G ' || true)"
[ -z "$bad_grep" ] && ok "every git grep for the token in SKILL.md uses -G" || bad "git grep without -G" "$bad_grep"

rm -rf "$chk/out" && mkdir -p "$chk/out/build.log"
rc=0; (cd "$chk" && bash "$ROOT/skills/setup-annotation-guard/scripts/checks.sh" "$chk/checks.txt" "$chk/out" >/dev/null 2>&1) || rc=$?
[ "$rc" = 2 ] && ! grep -q '^lint' "$chk/out/status.txt" && ok "exits 2, before running anything more, when a log can't be written" \
  || bad "log write failure" "exit $rc"

echo "docstring rule"
doc_rule="$(awk '/When Python docstrings are banned/{f=1} f && /^```yaml/{g=1; next} g && /^```/{exit} g' "$SKILL")"
printf 'id: no-docstrings-python\nlanguage: Python\nseverity: error\nmessage: m\n%s\n' "$doc_rule" > "$WORK/doc.yml"
# Lines 0, 2, 6, 9, 11, 13, 25 are docstrings by Python's own rules. f-strings,
# with or without {…}, and byte strings never are; the rest is ordinary code.
cat > "$WORK/doc.py" <<'EOF'
"""module"""
def f():
    """function"""
    print("call")
    return "value"
class A:
    """class"""
    s = "attribute"
def concatenated():
    "hello " "world"
def parenthesized():
    ("hello world")
def nested():
    (("hello"))
def fstring():
    f"{print(123)}"
def mixed():
    "x" f"{print(1)}"
def conditional(x):
    ("a" if x else "b")
def fplain():
    f"plain"
def bytes_():
    b"x"
def raw():
    r"raw doc"
EOF
got="$(ast-grep scan -r "$WORK/doc.yml" --json=stream "$WORK/doc.py" 2>/dev/null \
  | awk 'match($0, /"start":\{"line":[0-9]+/) { print substr($0, RSTART + 16, RLENGTH - 16) }' | sort -n | paste -sd' ' -)"
[ "$got" = "0 2 6 9 11 13 25" ] && ok "matches plain, raw, concatenated, and parenthesized docstrings; not f-, byte strings, or code" \
  || bad "docstrings only" "$got"

echo "rule test template"
# kinds_of <lang> — the comment kinds the kinds table gives a language.
kinds_of() {
  echo "$table" | awk -F'|' -v lang="$1" '{
    n = split($2, names, ",")
    for (i = 1; i <= n; i++) { gsub(/^ +| +$/, "", names[i]); if (names[i] == lang) { print $3; exit } }
  }' | grep -oE '`[a-z_]+`' | tr -d '`' | awk '!seen[$0]++'
}
# case_of <line>... — one YAML block scalar case.
case_of() { printf '  - |\n'; printf '    %s\n' "$@"; }
cell() { echo "$1" | sed -E 's/^ *`?//; s/`? *$//'; }
fixtures="$(awk '/^\| Language \| `<s>` \|/{f=1; next} f && /^\|/{print; next} f{exit}' "$SKILL" | tail -n +2)"
[ -n "$fixtures" ] || bad "fixture table found in SKILL.md" "nothing"
tpl="$WORK/tpl"
while IFS= read -r row; do
  IFS='|' read -r _ langs s str line block doc _ <<< "$row"
  s="$(cell "$s")"; str="$(cell "$str")"; line="$(cell "$line")"; block="$(cell "$block")"; doc="$(cell "$doc")"
  IFS=',' read -ra list <<< "$langs"
  for lang in "${list[@]}"; do
    lang="$(echo "$lang" | xargs)"
    kinds="$(kinds_of "$lang")"
    if [ -z "$kinds" ]; then bad "$lang is in the kinds table" "missing"; continue; fi
    rm -rf "$tpl"; mkdir -p "$tpl/rules" "$tpl/rule-tests"
    printf 'ruleDirs: [rules]\ntestConfigs:\n  - testDir: rule-tests\n' > "$tpl/sgconfig.yml"
    { echo "id: t"; echo "language: $(sg_lang "$lang")"; echo "severity: error"; echo "rule:"; echo "  any:"
      echo "$kinds" | sed 's/^/    - kind: /'
      [ "$lang" = HTML ] && printf '  not:\n    any:\n%s\n' "$html_text"; } > "$tpl/rules/t.yml"
    { echo "id: t"; echo "valid:"; case_of "$str"
      [ "$lang" = HTML ] && case_of '<textarea><!-- x --></textarea>'
      echo "invalid:"
      [ -n "$line" ] && { case_of "$line" "$s"; case_of "$s $line"; }
      [ -n "$block" ] && case_of "$block $s"
      [ -n "$doc" ] && case_of "$doc" "$s"
    } > "$tpl/rule-tests/t-test.yml"
    n="$(grep -c '^  - |' "$tpl/rule-tests/t-test.yml")"
    out="$(cd "$tpl" && ast-grep test --skip-snapshot-tests 2>&1)"
    if echo "$out" | grep -q '1 passed; 0 failed' && [ "$n" -ge 2 ]; then
      ok "$lang: string valid, every comment form invalid ($n cases)"
    else
      bad "$lang template" "$(echo "$out" | tail -3)"
    fi
  done
done <<< "$fixtures"

doc_test="$(awk '/^id: no-docstrings-python$/{f=1} f && /^```/{exit} f' "$SKILL")"
rm -rf "$tpl"; mkdir -p "$tpl/rules" "$tpl/rule-tests"
printf 'ruleDirs: [rules]\ntestConfigs:\n  - testDir: rule-tests\n' > "$tpl/sgconfig.yml"
cp "$WORK/doc.yml" "$tpl/rules/doc.yml"
printf '%s\n' "$doc_test" > "$tpl/rule-tests/doc-test.yml"
out="$(cd "$tpl" && ast-grep test --skip-snapshot-tests 2>&1)"
[ -n "$doc_test" ] && echo "$out" | grep -q '1 passed; 0 failed' && ok "docstring rule passes its fixed test" \
  || bad "docstring rule test" "$(echo "$out" | tail -3)"

echo "ledger and cleanup scope"
ledger_cmd="$(skill_cmd ledger.sh "$WORK/ls")"
led="$WORK/le,d"
mkdir -p "$led/rules" "$led/.github" "$WORK/ls"
git -C "$led" init -q
printf 'ruleDirs: [rules]\n# about the config\nlanguageGlobs:\n  Python: ["*.pyx"]\n' > "$led/sgconfig.yml"
printf 'id: no-comments-python\nlanguage: Python\nseverity: error\nrule:\n  kind: comment\n  not: { regex: "^# noqa: E501$" }\nfix: ""\n' > "$led/rules/c.yml"
printf 'id: no-comments-yaml\nlanguage: Yaml\nseverity: error\nrule: { kind: comment }\nfix: ""\n' > "$led/rules/y.yml"
# A rule the repo already had: neither the ledger nor the cleanup may use it.
printf 'id: prefer-two\nlanguage: Python\nseverity: error\nrule: { pattern: "x = 1" }\nfix: "x = 2"\n' > "$led/rules/other.yml"
printf '# a\nx = 1  # noqa: E501\n' > "$led/a.py"
printf 'y = 2  # b\n' > "$led/.github/b.py"
printf 'z = 3  # glob\n' > "$led/d.pyx"
printf '# ast-grep-ignore\n\n# hidden\n' > "$led/c.py"
git -C "$led" add -A
git -C "$led" -c user.name=t -c user.email=t@t commit -qm base
base="$(git -C "$led" rev-parse HEAD)"
# Edits this setup makes before the ledger: an existing config gains a line.
mkdir -p "$led/old"
printf 'ruleDirs:\n  - old\n  - rules\n# about the config\nlanguageGlobs:\n  Python: ["*.pyx"]\n' > "$led/sgconfig.yml"
echo "$base" > "$WORK/ls/base"
ledger_run="$ledger_cmd"
ledger_out="$(cd "$led" && eval "$ledger_run" 2>/dev/null | tail -1)"
rows="$(python3 -c '
import json, sys
for o in map(json.loads, open(sys.argv[1])):
    print(o["file"], o["range"]["start"]["line"], o["text"])
' "$WORK/ls/removed-comments.jsonl" 2>/dev/null | sort)"
want="$(printf '%s\n' '.github/b.py 0 # b' 'a.py 0 # a' 'c.py 0 # ast-grep_ignore' 'c.py 2 # hidden' 'd.pyx 0 # glob' 'sgconfig.yml 1 # about the config' | sort)"
[ -n "$ledger_cmd" ] && [ "$rows" = "$want" ] && [ "$ledger_out" = "ledger exit 0" ] \
  && ok "ledger: base positions, hidden dirs, suppressed files, the repo's languageGlobs; exceptions and other rules left out" \
  || bad "ledger rows" "$ledger_out: $(echo "$rows" | tr '\n' ';')"
mv "$led/sgconfig.yml" "$led/sgconfig.bak"
ledger_out="$(cd "$led" && eval "$ledger_run" 2>/dev/null | tail -1)"
[ "$ledger_out" != "ledger exit 0" ] && ok "ledger reports a failed scan" || bad "ledger failure" "$ledger_out"
mv "$led/sgconfig.bak" "$led/sgconfig.yml"
touch "$WORK/ls/base-tree"
ledger_out="$(cd "$led" && eval "$ledger_run" 2>/dev/null | tail -1)"
[ "$ledger_out" != "ledger exit 0" ] && grep -q 'ast-grep-ignore' "$led/c.py" \
  && ok "ledger stops, real repo untouched, when the checkout fails" || bad "blocked checkout" "$ledger_out"
rm "$WORK/ls/base-tree"
git -C "$led" worktree add -q --detach "$WORK/ls/base-tree" HEAD
ledger_out="$(cd "$led" && eval "$ledger_run" 2>/dev/null | tail -1)"
[ "$ledger_out" = "ledger exit 0" ] && [ ! -e "$WORK/ls/base-tree" ] \
  && ok "ledger clears the worktree an interrupted run left" || bad "leftover worktree" "$ledger_out"
plain="$WORK/plain"
mkdir -p "$plain/rules"
git -C "$plain" init -q
printf 'ruleDirs: [rules]\n' > "$plain/sgconfig.yml"
cp "$led/rules/c.yml" "$plain/rules/c.yml"
printf 'x = 1  # a\n' > "$plain/a.py"
git -C "$plain" add -A
git -C "$plain" -c user.name=t -c user.email=t@t commit -qm base
mkdir -p "$WORK/lp"
git -C "$plain" rev-parse HEAD > "$WORK/lp/base"
plain_run="$(skill_cmd ledger.sh "$WORK/lp")"
# This test runs under pipefail, where a bare `git grep` finding nothing fails the pipeline.
ledger_out="$(cd "$plain" && eval "$plain_run" 2>/dev/null | tail -1)"
[ "$ledger_out" = "ledger exit 0" ] && [ "$(wc -l < "$WORK/lp/removed-comments.jsonl" | tr -d ' ')" = 1 ] \
  && ok "ledger works with no ast-grep-ignore in the repo, under pipefail" || bad "no-token ledger" "$ledger_out"
git -C "$led" config grep.patternType not-a-type
ledger_out="$(set +o pipefail; cd "$led" && eval "$ledger_run" 2>/dev/null | tail -1)"
[ "$ledger_out" != "ledger exit 0" ] && ok "ledger stops when git grep fails, without pipefail" || bad "grep failure" "$ledger_out"
git -C "$led" config --unset grep.patternType
if command -v zsh >/dev/null; then
  rm -f "$WORK/lp/removed-comments.jsonl"
  ledger_out="$(cd "$plain" && zsh -c "$plain_run" 2>/dev/null | tail -1)"
  [ "$ledger_out" = "ledger exit 0" ] && ! git -C "$plain" worktree list | grep -q "$WORK/lp/base-tree" \
    && ok "ledger runs in zsh and removes its worktree" || bad "ledger in zsh" "$ledger_out"
fi
mkdir -p "$WORK/noperl"
printf '#!/bin/sh\nexit 42\n' > "$WORK/noperl/perl"; chmod +x "$WORK/noperl/perl"
ledger_out="$(cd "$led" && PATH="$WORK/noperl:$PATH" eval "$ledger_run" 2>/dev/null | tail -1)"
[ "$ledger_out" != "ledger exit 0" ] && ok "ledger stops when it can't unhide suppressed files" || bad "perl failure" "$ledger_out"
git -C "$led" worktree list | grep -q "$WORK/ls/base-tree" && bad "ledger removes its worktree" "still listed" \
  || ok "ledger removes its worktree"

echo "fix: '' removes comment text only"
mkdir -p "$WORK/fix"
cat > "$WORK/fix/rule.yml" <<'EOF'
id: no-comments-python
language: Python
rule: { kind: comment }
fix: ''
EOF
printf '# a\nx = 1  # b\ns = "# no"\n' > "$WORK/fix/a.py"
(cd "$WORK/fix" && ast-grep scan -r rule.yml -U a.py >/dev/null 2>&1)
got="$(cat "$WORK/fix/a.py")"
[ "$got" = "$(printf '\nx = 1  \ns = "# no"')" ] && ok "leaves a blank line and trailing spaces, keeps strings" \
  || bad "comment text removed" "$(printf '%s' "$got" | od -c | head -3)"

echo "suppression record"
sup="$WORK/sup"
mkdir -p "$sup/vendor" "$sup/rules" "$WORK/sp"
git -C "$sup" init -q
printf 'ruleDirs: [rules]\n' > "$sup/sgconfig.yml"
printf 'id: no-comments-python\nlanguage: Python\nseverity: error\nignores: ["vendor/**"]\nrule: { kind: comment }\nfix: ""\n' > "$sup/rules/c.yml"
printf 'x = 1\n' > "$sup/a.py"
printf '# ast-grep-ignore\n\n# hidden\n' > "$sup/vendor/a.py"
git -C "$sup" add -A
git -C "$sup" -c user.name=t -c user.email=t@t commit -qm base
git -C "$sup" rev-parse HEAD > "$WORK/sp/base"
out="$(cd "$sup" && zsh -c "$(skill_cmd ledger.sh "$WORK/sp")" 2>/dev/null | tail -1)"
[ "$out" = "ledger exit 0" ] && [ "$(cat "$WORK/sp/suppressions.txt")" = "vendor/a.py:1:# ast-grep-ignore" ] \
  && [ ! -s "$WORK/sp/removed-comments.jsonl" ] \
  && ok "records the token's line in a path the rules ignore, where the scan records nothing" \
  || bad "records the token" "$out: $(cat "$WORK/sp/suppressions.txt")"
rm "$WORK/sp/suppressions.txt" && mkdir "$WORK/sp/suppressions.txt"
out="$(cd "$sup" && bash -c "$(skill_cmd ledger.sh "$WORK/sp")" 2>/dev/null | tail -1)"
[ "$out" != "ledger exit 0" ] && ok "fails when the suppression record can't be written" || bad "record write failure" "$out"
rmdir "$WORK/sp/suppressions.txt"
rm "$sup/vendor/a.py"
git -C "$sup" add -A
git -C "$sup" -c user.name=t -c user.email=t@t commit -qm clean
git -C "$sup" rev-parse HEAD > "$WORK/sp/base"
out="$(cd "$sup" && bash -o pipefail -c "$(skill_cmd ledger.sh "$WORK/sp")" 2>/dev/null | tail -1)"
[ "$out" = "ledger exit 0" ] && [ ! -s "$WORK/sp/suppressions.txt" ] && ok "no token: exit 0 and an empty record" \
  || bad "no token" "$out"

echo "lint command"
lint="$(awk '/^## 4\./{f=1} f && /^```bash/{g=1; next} g && /^```/{exit} g' "$SKILL")"
[ -n "$lint" ] || bad "lint command found in SKILL.md section 4" "nothing"
repo="$WORK/repo"
mkdir -p "$repo/rules" "$repo/rule-tests"
git -C "$repo" init -q
printf 'ruleDirs: [rules]\ntestConfigs:\n  - testDir: rule-tests\n' > "$repo/sgconfig.yml"
cat > "$repo/rules/no-comments-python.yml" <<'EOF'
id: no-comments-python
language: Python
severity: error
message: Comments aren't allowed here. Say it in code.
rule:
  kind: comment
  not:
    any:
      - regex: '^# noqa: [A-Z]+[0-9]+(, ?[A-Z]+[0-9]+)*$'
EOF
cat > "$repo/rule-tests/no-comments-python-test.yml" <<'EOF'
id: no-comments-python
valid:
  - 'x = 1  # noqa: E501'
  - 's = "# no"'
invalid:
  - '# a'
  - 'x = 1  # b'
  - 'x = 1  # noqa'
  - |
    x = 1
    # b
EOF
printf 'x = 1  # noqa: E501\n' > "$repo/clean.py"
printf 'lint:\n\t%s\n' "$lint" > "$repo/Makefile"
git -C "$repo" add -A

# lint_case <name> <want-exit: 0|nonzero> — run the command from SKILL.md the
# way the skill wires it: pasted as is into a Makefile that is itself in the
# repo.
command -v make >/dev/null || { echo "make not found" >&2; exit 1; }
lint_case() {
  local rc=0
  make -s -C "$repo" lint >/dev/null 2>&1 || rc=$?
  if { [ "$2" = 0 ] && [ "$rc" = 0 ]; } || { [ "$2" = nonzero ] && [ "$rc" != 0 ]; }; then
    ok "$1"
  else
    bad "$1" "exit $rc"
  fi
}

lint_case "passes with allowed directives and the command in its own Makefile" 0

printf 'x = 1  # trailing\n' > "$repo/bad.py"
lint_case "fails on a comment" nonzero
rm "$repo/bad.py"

printf '# ast-grep-ignore\n\n# hidden\n' > "$repo/bypass.py"
rc=0; (cd "$repo" && ast-grep scan) >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] && ok "file-level ast-grep-ignore hides the whole file from scan alone" \
  || bad "file-level ignore hides the file" "scan exit $rc"
lint_case "fails on file-level ast-grep-ignore in an untracked file" nonzero
git -C "$repo" add bypass.py
lint_case "fails on file-level ast-grep-ignore in a tracked file" nonzero
git -C "$repo" rm -q --cached bypass.py; rm "$repo/bypass.py"

printf '# see ast-grep-ignore\n\n# hidden\n' > "$repo/bypass.py"
lint_case "fails when the token is anywhere in a first-line comment" nonzero
rm "$repo/bypass.py"

printf '/*\n ast-grep-ignore\n*/\n\n// hidden\n' > "$repo/bypass.js"
lint_case "fails on the token inside a block comment that starts on line 1" nonzero
rm "$repo/bypass.js"

printf '# ast-grep-ignore\n\n# hidden\n' > "$repo/a:b.py"
lint_case "fails on file-level ast-grep-ignore in a file named with a colon" nonzero
rm "$repo/a:b.py"

printf 'x = 1\ns = "ast-grep-ignore"\n' > "$repo/token.py"
lint_case "fails on the token in a string: it is banned everywhere" nonzero
rm "$repo/token.py"

mkdir -p "$repo/.hidden"
printf 'x = 1  # in a hidden directory\n' > "$repo/.hidden/a.py"
lint_case "fails on a comment in a hidden directory" nonzero
rm -r "$repo/.hidden"

printf 'x = 1  # inside .git\n' > "$repo/.git/a.py"
lint_case "ignores git's own directory" 0
rm "$repo/.git/a.py"

printf '# ast-grep-ignore\n\n# hidden\n' > "$repo/rules/bypass.py"
lint_case "fails on file-level ast-grep-ignore under rules/" nonzero
rm "$repo/rules/bypass.py"

git -C "$repo" config grep.patternType fixed
lint_case "passes on a clean repo with grep.patternType=fixed" 0
printf '# ast-grep-ignore\n\n# hidden\n' > "$repo/bypass.py"
lint_case "fails on the token even with grep.patternType=fixed" nonzero
rm "$repo/bypass.py"
git -C "$repo" config grep.patternType not-a-type
lint_case "fails when git grep itself fails" nonzero
git -C "$repo" config --unset grep.patternType
for shell in bash zsh; do
  command -v "$shell" >/dev/null || continue
  # pipefail_case <name> <want-exit: 0|nonzero> — the command run by <shell> under pipefail.
  pipefail_case() {
    local rc=0
    (cd "$repo" && "$shell" -o pipefail -c "$lint" >/dev/null 2>&1) || rc=$?
    if { [ "$2" = 0 ] && [ "$rc" = 0 ]; } || { [ "$2" = nonzero ] && [ "$rc" != 0 ]; }; then ok "$shell, pipefail: $1"; else bad "$shell, pipefail: $1" "exit $rc"; fi
  }
  pipefail_case "passes on a clean repo" 0
  printf '# ast-grep-ignore\n' > "$repo/bypass.py"
  pipefail_case "fails on the token" nonzero
  rm "$repo/bypass.py"
  git -C "$repo" config grep.patternType not-a-type
  pipefail_case "fails when git grep itself fails" nonzero
  git -C "$repo" config --unset grep.patternType
done

lint_case "passes again once the bypass is gone" 0

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
