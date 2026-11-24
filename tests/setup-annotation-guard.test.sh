#!/usr/bin/env bash
# Tests for the ast-grep claims in skills/setup-annotation-guard/SKILL.md.
# Offline, but needs an ast-grep binary: on PATH, or named by $AST_GREP.
# The comment-kinds table, the docstring rule, and the lint command are read
# from SKILL.md itself, so the skill and these tests can't drift apart.
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

echo "empty JSX expressions"
jsx_cmd="$(grep -m1 'id: empty-jsx' "$SKILL" | sed 's/<Tsx|JavaScript>/Tsx/')"
[ -n "$jsx_cmd" ] || bad "empty-jsx command found in SKILL.md" "nothing"
jsx="$WORK/jsx"
mkdir -p "$jsx/fixtures"
git -C "$jsx" init -q
printf 'const o = {/* x */};\nfunction f() {/* y */}\nconst v = <div>{/* a */}<span>{x}</span>{\n  /* b */\n}</div>;\n' > "$jsx/a.tsx"
printf 'const v = <div>{}</div>;\n' > "$jsx/fixtures/page.tsx"
git -C "$jsx" add -A
git -C "$jsx" -c user.name=t -c user.email=t@t commit -qm init
snap="$(git -C "$jsx" rev-parse HEAD)"
(cd "$jsx" && ast-grep scan --inline-rules '{id: c, language: Tsx, ignores: ["fixtures/**"], rule: {kind: comment}, fix: ""}' -U) >/dev/null 2>&1
(cd "$jsx" && bash -c "${jsx_cmd//<snap>/$snap}") >/dev/null 2>&1
got="$(cat "$jsx/a.tsx")"
[ "$got" = "$(printf 'const o = {};\nfunction f() {}\nconst v = <div><span>{x}</span></div>;')" ] \
  && ok "removes empty JSX containers, keeps object literals and blocks" || bad "empty JSX containers" "$got"
[ "$(cat "$jsx/fixtures/page.tsx")" = 'const v = <div>{}</div>;' ] \
  && ok "leaves files the comment removal didn't change" || bad "unchanged files left alone" "$(cat "$jsx/fixtures/page.tsx")"

echo "docstring rule"
doc_rule="$(awk '/When Python docstrings are banned/{f=1} f && /^```yaml/{g=1; next} g && /^```/{exit} g' "$SKILL")"
printf 'id: no-docstrings-python\nlanguage: Python\nseverity: error\nmessage: m\n%s\n' "$doc_rule" > "$WORK/doc.yml"
# Lines 0, 2, 6, 9, 11, 13 are docstrings by Python's own rules. The
# f-strings run code and are never docstrings; the rest are ordinary code.
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
EOF
got="$(ast-grep scan -r "$WORK/doc.yml" --json=stream "$WORK/doc.py" 2>/dev/null \
  | awk 'match($0, /"start":\{"line":[0-9]+/) { print substr($0, RSTART + 16, RLENGTH - 16) }' | sort -n | paste -sd' ' -)"
[ "$got" = "0 2 6 9 11 13" ] && ok "matches plain, concatenated, and parenthesized docstrings; not f-strings or code" \
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
      echo "$kinds" | sed 's/^/    - kind: /'; } > "$tpl/rules/t.yml"
    { echo "id: t"; echo "valid:"; case_of "$str"; echo "invalid:"
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
ledger_cmd="$(awk '/^Then record every comment the cleanup will remove/{f=1} f && /^```bash/{g=1; next} g && /^```/{exit} g' "$SKILL")"
cleanup_cmd="$(grep -m1 "^ast-grep scan .* -U$" "$SKILL")"
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
ledger_run="$(echo "$ledger_cmd" | sed -e "s|<scratchpad>|$WORK/ls|g" -e "s|<base>|$base|g")"
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
touch "$WORK/ls/base"
ledger_out="$(cd "$led" && eval "$ledger_run" 2>/dev/null | tail -1)"
[ "$ledger_out" != "ledger exit 0" ] && grep -q 'ast-grep-ignore' "$led/c.py" \
  && ok "ledger stops, real repo untouched, when the checkout fails" || bad "blocked checkout" "$ledger_out"
rm "$WORK/ls/base"
plain="$WORK/plain"
mkdir -p "$plain/rules"
git -C "$plain" init -q
printf 'ruleDirs: [rules]\n' > "$plain/sgconfig.yml"
cp "$led/rules/c.yml" "$plain/rules/c.yml"
printf 'x = 1  # a\n' > "$plain/a.py"
git -C "$plain" add -A
git -C "$plain" -c user.name=t -c user.email=t@t commit -qm base
plain_run="$(echo "$ledger_cmd" | sed -e "s|<scratchpad>|$WORK/lp|g" -e "s|<base>|$(git -C "$plain" rev-parse HEAD)|g")"
mkdir -p "$WORK/lp"
# This test runs under pipefail, where a bare `git grep` finding nothing fails the pipeline.
ledger_out="$(cd "$plain" && eval "$plain_run" 2>/dev/null | tail -1)"
[ "$ledger_out" = "ledger exit 0" ] && [ "$(wc -l < "$WORK/lp/removed-comments.jsonl" | tr -d ' ')" = 1 ] \
  && ok "ledger works with no ast-grep-ignore in the repo, under pipefail" || bad "no-token ledger" "$ledger_out"
git -C "$led" config grep.patternType not-a-type
ledger_out="$(set +o pipefail; cd "$led" && eval "$ledger_run" 2>/dev/null | tail -1)"
[ "$ledger_out" != "ledger exit 0" ] && ok "ledger stops when git grep fails, without pipefail" || bad "grep failure" "$ledger_out"
git -C "$led" config --unset grep.patternType
mkdir -p "$WORK/noperl"
printf '#!/bin/sh\nexit 42\n' > "$WORK/noperl/perl"; chmod +x "$WORK/noperl/perl"
ledger_out="$(cd "$led" && PATH="$WORK/noperl:$PATH" eval "$ledger_run" 2>/dev/null | tail -1)"
[ "$ledger_out" != "ledger exit 0" ] && ok "ledger stops when it can't unhide suppressed files" || bad "perl failure" "$ledger_out"
git -C "$led" worktree list | grep -q "$WORK/ls/base" && bad "ledger removes its worktree" "still listed" \
  || ok "ledger removes its worktree"
(cd "$led" && eval "$cleanup_cmd") >/dev/null 2>&1
[ -n "$cleanup_cmd" ] && [ "$(cat "$led/a.py")" = "$(printf '\nx = 1  # noqa: E501')" ] \
  && ok "cleanup applies only the guard's fixes" || bad "cleanup scope" "$(cat "$led/a.py")"

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

lint_case "passes again once the bypass is gone" 0

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
