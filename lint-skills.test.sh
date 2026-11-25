#!/usr/bin/env bash
# Tests for lint-skills.sh. Offline: each case builds a small repo in a temp
# dir, breaks one rule, and checks the lint fails on it and only it.
#
#   bash lint-skills.test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
LINT="$ROOT/lint-skills.sh"
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
  out="$(bash "$LINT" "$r" 2>&1)" || rc=$?
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
  out="$(bash "$LINT" "$r" 2>&1)" || rc=$?
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
  "sed -i.bak 's/^description: .*/description: >/' skills/alpha/SKILL.md"
expect_fail "a description that runs onto a second line" "description must be on the description: line" \
  "sed -i.bak 's/^description: .*/description: Do the alpha\\n  thing./' skills/alpha/SKILL.md"
expect_fail "a description past 1024 characters" "description is 1025 characters" \
  "sed -i.bak \"s/^description: .*/description: \$(printf 'a%.0s' \$(seq 1025))/\" skills/alpha/SKILL.md"
expect_fail "disable-model-invocation: false" "disable-model-invocation is 'false'" \
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

out="$(bash "$LINT" 2>&1)" && ok "this repo passes" || bad "this repo passes" "$out"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
