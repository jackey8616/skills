#!/usr/bin/env bash
# Tests for lint-skills.py. Offline: each case builds a small repo in a temp
# dir, breaks one rule, and checks the lint fails on it and only it.
#
#   bash lint-skills.test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
LINT="$ROOT/lint-skills.py"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0
ok()   { pass=$((pass + 1)); echo "  ok   $1"; }
bad()  { fail=$((fail + 1)); echo "  FAIL $1 — got: $2"; }

# fixture <dir> — a repo that passes: `alpha` user-invoked, `beta`
# model-invoked with a script and its listed test.
fixture() {
  local r="$1"
  mkdir -p "$r/skills/alpha/agents" "$r/skills/beta/agents" "$r/skills/beta/scripts" "$r/skills/beta/tests"
  cat > "$r/skills/alpha/SKILL.md" <<'EOF'
---
name: alpha
description: Do the alpha thing.
disable-model-invocation: true
---

# Alpha
EOF
  cat > "$r/skills/alpha/agents/openai.yaml" <<'EOF'
interface:
  display_name: "Alpha"
  short_description: "Do the alpha thing"
policy:
  allow_implicit_invocation: false
EOF
  cat > "$r/skills/beta/SKILL.md" <<'EOF'
---
name: beta
description: Do the beta thing. Use when the user asks for beta.
---

Run `bash "${CLAUDE_SKILL_DIR}/scripts/run.sh"`.
EOF
  cat > "$r/skills/beta/agents/openai.yaml" <<'EOF'
interface:
  display_name: "Beta"
  short_description: "Do the beta thing"
EOF
  echo 'echo beta' > "$r/skills/beta/scripts/run.sh"
  echo 'true' > "$r/skills/beta/tests/run.test.sh"
  cat > "$r/README.md" <<'EOF'
| Skill | What it does |
| ----- | ------------ |
| [`alpha`](skills/alpha/SKILL.md) | Alpha. |
| [`beta`](skills/beta/SKILL.md) | Beta. |
EOF
  cat > "$r/CLAUDE.md" <<'EOF'
- `bash skills/beta/tests/run.test.sh` — `skills/beta/scripts/run.sh`
EOF
}

# expect_fail <name> <want> <setup> — build a fixture, run <setup> in it, and
# pass only if the lint exits 1 with exactly one FAIL line, containing <want>.
expect_fail() {
  local name="$1" want="$2" setup="$3" r="$WORK/$pass-$fail"
  fixture "$r"
  (cd "$r" && eval "$setup")
  local out rc=0
  out="$(python3 "$LINT" "$r" 2>&1)" || rc=$?
  if [ "$rc" -eq 1 ] && [ "$(printf '%s\n' "$out" | grep -c '^FAIL')" -eq 1 ] &&
     printf '%s\n' "$out" | grep '^FAIL' | grep -Fq "$want"; then
    ok "$name"
  else
    bad "$name" "exit $rc, output: $out"
  fi
}

# expect_pass <name> <setup> [want-warn] — build a fixture, run <setup>, and
# pass only if the lint exits 0, printing <want-warn> if one is given.
expect_pass() {
  local name="$1" setup="$2" want="${3:-}" r="$WORK/$pass-$fail"
  fixture "$r"
  (cd "$r" && eval "$setup")
  local out rc=0
  out="$(python3 "$LINT" "$r" 2>&1)" || rc=$?
  if [ "$rc" -eq 0 ] && { [ -z "$want" ] || printf '%s\n' "$out" | grep -Fq "$want"; }; then
    ok "$name"
  else
    bad "$name" "exit $rc, output: $out"
  fi
}

expect_pass "the fixture passes" ":"
expect_pass "a SKILL.md past 500 lines only warns" \
  "seq 600 >> skills/alpha/SKILL.md" "WARN skills/alpha/SKILL.md: 607 lines"
expect_pass "a quoted name and description pass" \
  "sed -i.bak -e 's/^name: alpha/name: \"alpha\"/' -e 's/^description: \\(.*\\)/description: \"\\1\"/' skills/alpha/SKILL.md"
expect_pass "a path at the end of a sentence" \
  "echo 'See \${CLAUDE_SKILL_DIR}/scripts/run.sh.' >> skills/beta/SKILL.md"
expect_pass "a skill without scripts needs no tests" \
  "rm -r skills/beta/scripts skills/beta/tests && sed -i.bak '/CLAUDE_SKILL_DIR/d' skills/beta/SKILL.md && : > CLAUDE.md"

expect_fail "a directory without SKILL.md" "skills/gamma: no SKILL.md" \
  "mkdir skills/gamma"
expect_fail "no frontmatter" "skills/alpha/SKILL.md: no frontmatter" \
  "printf '# Alpha\n' > skills/alpha/SKILL.md"
expect_fail "frontmatter that never closes" "skills/alpha/SKILL.md: no frontmatter" \
  "printf -- '---\nname: alpha\n' > skills/alpha/SKILL.md"
expect_fail "name differs from the directory" "name is 'alfa', the directory is 'alpha'" \
  "sed -i.bak 's/^name: alpha/name: alfa/' skills/alpha/SKILL.md"
expect_fail "uppercase directory name" "name must be lowercase" \
  "mv skills/alpha skills/Alpha && sed -i.bak -e 's/^name: alpha/name: Alpha/' skills/Alpha/SKILL.md && sed -i.bak 's|alpha|Alpha|g' README.md"
expect_fail "no description" "skills/alpha/SKILL.md: no description" \
  "sed -i.bak '/^description:/d' skills/alpha/SKILL.md"
expect_fail "a block-scalar description" "description must be on the description: line" \
  "sed -i.bak 's/^description: .*/description: >\\n  Do the alpha thing./' skills/alpha/SKILL.md"
expect_fail "a description that runs onto a second line" "description must be on the description: line" \
  "sed -i.bak 's/^description: .*/description: Do the alpha\\n  thing./' skills/alpha/SKILL.md"
expect_fail "a description past 1024 characters" "description is 1025 characters" \
  "sed -i.bak \"s/^description: .*/description: \$(printf 'a%.0s' \$(seq 1025))/\" skills/alpha/SKILL.md"
expect_fail "disable-model-invocation: false" "disable-model-invocation is false;" \
  "sed -i.bak 's/^disable-model-invocation: true/disable-model-invocation: false/' skills/alpha/SKILL.md && sed -i.bak '/policy/,\$d' skills/alpha/agents/openai.yaml && sed -i.bak 's/thing\\.\$/thing. Use when asked./' skills/alpha/SKILL.md"
expect_fail "user-invoked with trigger phrasing" "user-invoked, so the description has no \"Use when\" trigger" \
  "sed -i.bak 's/^description: .*/description: Use when the user asks for alpha./' skills/alpha/SKILL.md"
expect_fail "model-invoked without trigger phrasing" "model-invoked, so the description needs \"Use when\" trigger" \
  "sed -i.bak 's/^description: .*/description: Do the beta thing./' skills/beta/SKILL.md"
expect_fail "no agents/openai.yaml" "skills/alpha: no agents/openai.yaml" \
  "rm skills/alpha/agents/openai.yaml"
expect_fail "openai.yaml without display_name" "no interface.display_name" \
  "sed -i.bak '/display_name/d' skills/beta/agents/openai.yaml"
expect_fail "openai.yaml without short_description" "no interface.short_description" \
  "sed -i.bak '/short_description/d' skills/beta/agents/openai.yaml"
expect_fail "user-invoked in SKILL.md only" "user-invoked in SKILL.md, but agents/openai.yaml lacks" \
  "sed -i.bak '/policy/,\$d' skills/alpha/agents/openai.yaml"
expect_fail "user-invoked with allow_implicit_invocation: true" "user-invoked in SKILL.md, but agents/openai.yaml lacks" \
  "sed -i.bak 's/allow_implicit_invocation: false/allow_implicit_invocation: true/' skills/alpha/agents/openai.yaml"
expect_fail "user-invoked with the setting outside policy:" "user-invoked in SKILL.md, but agents/openai.yaml lacks" \
  "sed -i.bak '/^policy:/d' skills/alpha/agents/openai.yaml"
expect_fail "model-invoked with a policy block in openai.yaml" "model-invoked in SKILL.md, so agents/openai.yaml has no policy block" \
  "printf 'policy:\n  allow_implicit_invocation: false\n' >> skills/beta/agents/openai.yaml"
expect_fail "missing from the README table" "skills/beta: no row in README.md" \
  "sed -i.bak '/beta/d' README.md"
expect_fail "README links a skill that doesn't exist" "README.md: links skills/gone/SKILL.md" \
  "echo '| [\`gone\`](skills/gone/SKILL.md) | Gone. |' >> README.md"
expect_fail "SKILL.md points at a missing script" "points at \${CLAUDE_SKILL_DIR}/scripts/run.sh" \
  "rm skills/beta/scripts/run.sh && echo x > skills/beta/scripts/other.sh"
expect_fail "scripts without tests" "skills/beta: has scripts/ but no tests/*.test.sh" \
  "rm skills/beta/tests/run.test.sh && sed -i.bak '/run.test.sh/d' CLAUDE.md"
expect_fail "a test not listed in CLAUDE.md" "skills/beta/tests/run.test.sh: not listed" \
  "sed -i.bak '/run.test.sh/d' CLAUDE.md"
expect_fail "a root test not listed in CLAUDE.md" "install.test.sh: not listed" \
  "touch install.test.sh"

expect_pass "a path ending a question or an exclamation" \
  "printf 'Did you run \${CLAUDE_SKILL_DIR}/scripts/run.sh?\nRun \${CLAUDE_SKILL_DIR}/scripts/run.sh!\n' >> skills/beta/SKILL.md"
expect_pass "\"because when\" isn't \"Use when\"" \
  "sed -i.bak 's/^description: .*/description: Rewrite it, because when it is shallow the work is too./' skills/alpha/SKILL.md"
expect_pass "a 1024-character non-ASCII description" \
  "sed -i.bak \"s/^description: .*/description: \$(printf '—%.0s' \$(seq 1024))/\" skills/alpha/SKILL.md"
expect_fail "a 1025-character non-ASCII description" "description is 1025 characters" \
  "sed -i.bak \"s/^description: .*/description: \$(printf '—%.0s' \$(seq 1025))/\" skills/alpha/SKILL.md"
expect_pass "inline comments in openai.yaml" \
  "sed -i.bak -e 's/^policy:/policy:  # note/' -e 's/allow_implicit_invocation: false/& # user-invoked/' -e 's/^interface:/interface: # ui/' skills/alpha/agents/openai.yaml"
expect_fail "display_name outside interface:" "no interface.display_name" \
  "printf 'interface:\n  short_description: \"Do it\"\npolicy:\n  allow_implicit_invocation: false\n  display_name: \"Alpha\"\n' > skills/alpha/agents/openai.yaml"

expect_fail "a continuation after a blank line" "description must be on the description: line" \
  "sed -i.bak 's/^description: .*/description: Do the alpha\n\n  thing./' skills/alpha/SKILL.md"
expect_fail "a comment line inside the description" "SKILL.md frontmatter: not valid YAML" \
  "sed -i.bak 's/^description: .*/description: Do the alpha\n# note\n  thing./' skills/alpha/SKILL.md"
expect_pass "a quoted one-line description starting with |" \
  "sed -i.bak 's/^description: .*/description: \"| pipes and filters, done the alpha way.\"/' skills/alpha/SKILL.md"
expect_pass "an inline comment on disable-model-invocation" \
  "sed -i.bak 's/^disable-model-invocation: true/& # user-invoked/' skills/alpha/SKILL.md"
expect_pass "a long inline comment after a short description" \
  "sed -i.bak \"s/^description: .*/description: Do it. # \$(printf 'a%.0s' \$(seq 1100))/\" skills/alpha/SKILL.md"
expect_fail "allow_implicit_invocation: \"false\" is a string" "user-invoked in SKILL.md, but agents/openai.yaml lacks" \
  "sed -i.bak 's/allow_implicit_invocation: false/allow_implicit_invocation: \"false\"/' skills/alpha/agents/openai.yaml"
expect_fail "an empty single-quoted display_name" "no interface.display_name" \
  "sed -i.bak \"s/display_name: .*/display_name: ''/\" skills/alpha/agents/openai.yaml"
expect_fail "openai.yaml that isn't valid YAML" "skills/alpha/agents/openai.yaml: not valid YAML" \
  "printf 'interface: [\n' > skills/alpha/agents/openai.yaml"
expect_fail "a skill's test outside tests/" "skills/beta/other/x.test.sh: tests sit at the repo root or in skills/<name>/tests/" \
  "mkdir skills/beta/other && touch skills/beta/other/x.test.sh && echo '- \`bash skills/beta/other/x.test.sh\`' >> CLAUDE.md"

expect_fail "a description on the line after the key" "description must be on the description: line" \
  "sed -i.bak 's/^description: .*/description:\n  Do the alpha thing./' skills/alpha/SKILL.md"
expect_fail "a quoted description on the line after the key" "description must be on the description: line" \
  "sed -i.bak 's/^description: .*/description:\n  \"Do the alpha thing.\"/' skills/alpha/SKILL.md"
expect_fail "a duplicate key in the frontmatter" "frontmatter: description: appears twice" \
  "sed -i.bak 's/^description: .*/description: Short.\ndescription: Do the alpha thing./' skills/alpha/SKILL.md"
expect_fail "a description from a merge key" "description must be on the description: line" \
  "sed -i.bak 's/^description: .*/d: \&d {description: Do the alpha thing.}\n<<: *d/' skills/alpha/SKILL.md"
expect_fail "frontmatter that isn't a mapping" "frontmatter: must be a YAML mapping" \
  "printf -- '---\n- a\n- b\n---\n' > skills/alpha/SKILL.md"
expect_fail "a test outside the root and skills/<name>/tests/" "tools/x.test.sh: tests sit at the repo root or in skills/<name>/tests/" \
  "mkdir tools && touch tools/x.test.sh && echo '- \`bash tools/x.test.sh\`' >> CLAUDE.md"
expect_fail "a skill linked in prose but not in a table row" "skills/beta: no row in README.md" \
  "sed -i.bak '/beta/d' README.md && echo 'See [\`beta\`](skills/beta/SKILL.md) in prose.' >> README.md"
expect_fail "README links a skill directory that doesn't exist" "README.md: links skills/gone/" \
  "echo '| [\`gone\`](skills/gone/) | Gone. |' >> README.md"
expect_pass "a path followed by a comma, a colon, or a semicolon" \
  "printf 'Run \${CLAUDE_SKILL_DIR}/scripts/run.sh, \${CLAUDE_SKILL_DIR}/scripts/run.sh: \${CLAUDE_SKILL_DIR}/scripts/run.sh;\n' >> skills/beta/SKILL.md"

expect_fail "a key written twice under policy:" "policy.allow_implicit_invocation: appears twice" \
  "sed -i.bak 's/  allow_implicit_invocation: false/  allow_implicit_invocation: true\n&/' skills/alpha/agents/openai.yaml"
expect_fail "a key written twice under a frontmatter mapping" "metadata.a: appears twice" \
  "sed -i.bak 's/^name: alpha/&\nmetadata:\n  a: 1\n  a: 2/' skills/alpha/SKILL.md"
expect_fail "a hidden test file CI's glob skips" ".hidden.test.sh: tests sit at the repo root or in skills/<name>/tests/" \
  "touch .hidden.test.sh && echo '- \`bash .hidden.test.sh\`' >> CLAUDE.md"
expect_fail "a test nested below tests/" "skills/beta/tests/sub/x.test.sh: tests sit at the repo root or in skills/<name>/tests/" \
  "mkdir skills/beta/tests/sub && touch skills/beta/tests/sub/x.test.sh && echo '- \`bash skills/beta/tests/sub/x.test.sh\`' >> CLAUDE.md"
expect_fail "a skill linked in a row's second column" "skills/beta: no row in README.md" \
  "sed -i.bak '/beta/d' README.md && echo '| Beta | [\`beta\`](skills/beta/SKILL.md) |' >> README.md"
expect_fail "a reference-style README link to a missing skill" "README.md: links skills/gone/SKILL.md" \
  "echo '[gone]: skills/gone/SKILL.md' >> README.md"
expect_fail "a ./skills README link to a missing skill" "README.md: links skills/gone2/SKILL.md" \
  "echo 'See [x](./skills/gone2/SKILL.md).' >> README.md"
expect_pass "a README link with a title" \
  "echo 'See [\`beta\`](skills/beta/SKILL.md \"Beta\").' >> README.md"
expect_fail "disable-model-invocation: yes" "disable-model-invocation is yes; write it as true" \
  "sed -i.bak 's/^disable-model-invocation: true/disable-model-invocation: yes/' skills/alpha/SKILL.md"
expect_fail "allow_implicit_invocation: off" "policy.allow_implicit_invocation is off; write it as false" \
  "sed -i.bak 's/allow_implicit_invocation: false/allow_implicit_invocation: off/' skills/alpha/agents/openai.yaml"

expect_fail "disable-model-invocation from a merge key" "disable-model-invocation is merged in; write it as true" \
  "sed -i.bak 's/^disable-model-invocation: true/d: \&d {disable-model-invocation: true}\n<<: *d/' skills/alpha/SKILL.md"
expect_fail "allow_implicit_invocation from a merge key" "policy.allow_implicit_invocation is merged in; write it as false" \
  "printf 'interface:\n  display_name: \"Alpha\"\n  short_description: \"x\"\nbase: &b {allow_implicit_invocation: false}\npolicy:\n  <<: *b\n' > skills/alpha/agents/openai.yaml"

fake="$WORK/no-yaml"
mkdir -p "$fake/yaml"
echo 'raise ImportError("no yaml here")' > "$fake/yaml/__init__.py"
rc=0; got="$(PYTHONPATH="$fake" python3 "$LINT" 2>&1)" || rc=$?
[ "$rc" -eq 2 ] && [ "$got" = "PyYAML not found. Install it: pip install pyyaml" ] \
  && ok "no PyYAML: exit 2 with the install command" || bad "no PyYAML" "exit $rc, output: $got"

out="$(python3 "$LINT" 2>&1)" && ok "this repo passes" || bad "this repo passes" "$out"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
