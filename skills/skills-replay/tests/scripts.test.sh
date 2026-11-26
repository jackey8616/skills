#!/usr/bin/env bash
# Tests for skills/skills-replay/scripts/replay.py. Offline: a made-up repo
# with one PR, a made-up skills repo, and a fake `claude` that fixes the bug
# only when the skill is loaded.
#
#   bash skills/skills-replay/tests/scripts.test.sh
set -uo pipefail

REPLAY="$(cd "$(dirname "$0")/../scripts" && pwd)/replay.py"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0
ok()   { pass=$((pass + 1)); echo "  ok   $1"; }
bad()  { fail=$((fail + 1)); echo "  FAIL $1 — got: $2"; }
check() { if eval "$2"; then ok "$1"; else bad "$1" "$3"; fi; }
commit() { git -C "$1" add -A && git -C "$1" -c user.name=t -c user.email=t@t commit -qm "$2"; }

# The repo: add.sh subtracts; the PR makes it add and brings a test for it.
# The base also holds a project skill and old replay files, which every
# snapshot must drop.
repo="$WORK/app"
mkdir -p "$repo/.claude/skills/local" "$repo/.skills-replay/old"
git -C "$repo" init -q -b main
printf '#!/usr/bin/env bash\necho $(( $1 - $2 ))\n' > "$repo/add.sh"
echo 'x' > "$repo/.claude/skills/local/SKILL.md"
echo 'x' > "$repo/.skills-replay/old/task.yaml"
commit "$repo" base
base=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" checkout -qb fix
printf '#!/usr/bin/env bash\necho $(( $1 + $2 ))\n' > "$repo/add.sh"
printf '#!/usr/bin/env bash\n[ "$(bash add.sh 2 3)" = 5 ]\n' > "$repo/test_add.sh"
commit "$repo" fix
head=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" checkout -q main
git -C "$repo" remote add origin https://example.invalid/app.git

skills="$WORK/skills-repo"
mkdir -p "$skills/skills/widget/tests"
git -C "$skills" init -q -b main
echo 'v1' > "$skills/skills/widget/SKILL.md"
echo 'secret case' > "$skills/skills/widget/tests/case.md"
commit "$skills" v1
v1=$(git -C "$skills" rev-parse --short HEAD)
echo 'v2' > "$skills/skills/widget/SKILL.md"
commit "$skills" v2
v2=$(git -C "$skills" rev-parse --short HEAD)

mkdir -p "$repo/.skills-replay/app-pr7"
task="$repo/.skills-replay/app-pr7/task.yaml"
cat > "$task" <<EOF
id: app-pr7
pr: 7
merged_at: 2026-01-02
base: $base
head: $head
prompt: |
  /widget fix add
plain_prompt: |
  Fix add.sh so it adds.
skills:
  - name: widget
    repo: $skills
    ref: $v1
setup:
  - touch setup-ran
hidden_tests: [test_add.sh]
test_command: bash test_add.sh
checks:
  - name: syntax
    run: bash -n add.sh
rubric: [add.sh adds]
max_turns: 5
timeout_seconds: 60
EOF

# The fake claude: logs what it sees, fixes add.sh only with the skill, and
# without it reaches for the PR with `gh pr view`.
fakebin="$WORK/bin"
log="$WORK/log"
mkdir -p "$fakebin" "$log"
cat > "$fakebin/claude" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then echo "9.9.9 (Fake Code)"; exit 0; fi
d="$FAKE_LOG/$(date +%s%N)"
mkdir -p "$d"
printf '%s\n' "$@" > "$d/argv"
pwd > "$d/cwd"
ls -A "$CLAUDE_CONFIG_DIR/skills" > "$d/skills"
[ -d "$CLAUDE_CONFIG_DIR/skills/widget" ] && ls -A "$CLAUDE_CONFIG_DIR/skills/widget" > "$d/widget" && cat "$CLAUDE_CONFIG_DIR/skills/widget/SKILL.md" > "$d/widget-version"
echo "${GH_TOKEN:-unset}" > "$d/gh"
git log --oneline | wc -l > "$d/commits"
git remote | wc -l > "$d/remotes"
ls -A > "$d/files"
if [ -d "$CLAUDE_CONFIG_DIR/skills/widget" ]; then
  sed -i 's/-/+/' add.sh
  echo '{"type":"assistant","message":{"content":[{"type":"text","text":"Fixing."},{"type":"tool_use","name":"Edit","input":{"file_path":"add.sh"}}]}}'
else
  echo '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"gh pr view 7"}}]}}'
  echo '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"title: fix add"}]}}'
  echo '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t2","name":"Bash","input":{"command":"git fetch origin"}}]}}'
  echo '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t2","is_error":true,"content":"Permission denied"}]}}'
fi
echo 'not json'
echo '[1]'
echo '{"type":"system","message":"Permission to use Bash has been denied."}'
echo '{"type":"result","subtype":"success","num_turns":3,"total_cost_usd":0.5,"duration_ms":120000,"result":"Done."}'
EOF
chmod +x "$fakebin/claude"
export PATH="$fakebin:$PATH" FAKE_LOG="$log" GH_TOKEN=leaky

echo "doctor"
check "doctor finds the tools" 'python3 "$REPLAY" doctor >/dev/null' "nonzero"

echo "dry run"
out=$(python3 "$REPLAY" run "$task" "$WORK/dry" --model none --runs 0 2>&1)
d="$WORK/dry/app-pr7/$(date +%F)-none"
check "prints the label dir" '[ "$(echo "$out" | tail -1)" = "$d" ]' "$out"
check "no model call" '[ -z "$(ls -A "$log")" ]' "$(ls "$log")"
check "hidden tests fail on the base" 'python3 -c "import json,sys; sys.exit(json.load(open(\"$d/base-check.json\"))[\"hidden_tests\"][\"passed\"])"' "$(cat "$d/base-check.json")"
check "the original PR passes them" 'python3 -c "import json,sys; c=json.load(open(\"$d/reference/checks.json\")); sys.exit(not (c[\"hidden_tests\"][\"passed\"] and c[\"checks\"][0][\"passed\"]))"' "$(cat "$d/reference/checks.json")"
check "the reference diff is the PR" 'grep -q "+echo \$(( \$1 + \$2 ))" "$d/reference/changes.diff" && grep -q test_add.sh "$d/reference/changes.diff"' "$(cat "$d/reference/changes.diff")"
check "setup is not in the reference diff" '! grep -q setup-ran "$d/reference/changes.diff"' "$(cat "$d/reference/changes.diff")"
check "a second run to the same label is refused" '! python3 "$REPLAY" run "$task" "$WORK/dry" --model none --runs 0 >/dev/null 2>&1' "accepted"

echo "run"
out=$(python3 "$REPLAY" run "$task" "$WORK/b" --model claude-test-1 --runs 1 -j 1 2>&1)
d="$WORK/b/app-pr7/$(date +%F)-claude-test-1"
check "both arms ran" '[ -f "$d/plain/run-1/meta.json" ] && [ -f "$d/skill/run-1/meta.json" ]' "$out"
plain_log=$(grep -l '^Fix add.sh so it adds.$' "$log"/*/argv | xargs dirname)
skill_log=$(grep -l '^/widget fix add$' "$log"/*/argv | xargs dirname)
check "plain gets plain_prompt, skill gets prompt" '[ -n "$plain_log" ] && [ -n "$skill_log" ]' "$(cat "$log"/*/argv)"
check "plain loads no skill" '[ -z "$(cat "$plain_log/skills")" ]' "$(cat "$plain_log/skills")"
check "skill loads only the skill" '[ "$(cat "$skill_log/skills")" = widget ]' "$(cat "$skill_log/skills")"
check "the skill is at its recorded ref" '[ "$(cat "$skill_log/widget-version")" = v1 ]' "$(cat "$skill_log/widget-version")"
check "the skill comes without its tests" '! grep -q tests "$skill_log/widget"' "$(cat "$skill_log/widget")"
check "GH_TOKEN is unset in the run" '[ "$(cat "$plain_log/gh")" = unset ]' "$(cat "$plain_log/gh")"
check "the project has no remote" '[ "$(cat "$plain_log/remotes")" -eq 0 ]' "$(cat "$plain_log/remotes")"
check "the project has only base and setup commits" '[ "$(cat "$plain_log/commits")" -eq 2 ]' "$(cat "$plain_log/commits")"
check "the project drops .claude/skills and .skills-replay" '! grep -qE "^(\.claude|\.skills-replay)$" "$plain_log/files"' "$(cat "$plain_log/files")"
check "the project path names nothing" '! grep -qE "app|pr7|plain|skill" "$plain_log/cwd"' "$(cat "$plain_log/cwd")"
check "gh and web tools are denied" 'grep -q "^Bash(gh:\*)$" "$plain_log/argv" && grep -q "^WebFetch$" "$plain_log/argv" && grep -q "^--strict-mcp-config$" "$plain_log/argv"' "$(cat "$plain_log/argv")"
check "the model is passed exactly" 'grep -q "^claude-test-1$" "$plain_log/argv"' "$(cat "$plain_log/argv")"
check "skill run passes the hidden tests" 'python3 -c "import json,sys; sys.exit(not json.load(open(\"$d/skill/run-1/checks.json\"))[\"hidden_tests\"][\"passed\"])"' "$(cat "$d/skill/run-1/checks.json")"
check "plain run fails them" 'python3 -c "import json,sys; sys.exit(json.load(open(\"$d/plain/run-1/checks.json\"))[\"hidden_tests\"][\"passed\"])"' "$(cat "$d/plain/run-1/checks.json")"
check "the skill run's diff is its change alone" 'grep -q "+echo \$(( \$1 + \$2 ))" "$d/skill/run-1/changes.diff" && ! grep -q test_add.sh "$d/skill/run-1/changes.diff"' "$(cat "$d/skill/run-1/changes.diff")"
check "meta records cost, turns, the ref" 'python3 -c "import json,sys; m=json.load(open(\"$d/skill/run-1/meta.json\")); sys.exit(not (m[\"cost_usd\"]==0.5 and m[\"turns\"]==3 and m[\"skills\"]==[{\"name\":\"widget\",\"ref\":\"$v1\"}] and m[\"changed\"]))"' "$(cat "$d/skill/run-1/meta.json")"
check "a plain run reaching for the PR is flagged" 'grep -q "gh (pr|api)" "$d/plain/run-1/meta.json"' "$(cat "$d/plain/run-1/meta.json")"
check "a refused call is not flagged" '! grep -q "git (fetch" "$d/plain/run-1/meta.json"' "$(cat "$d/plain/run-1/meta.json")"
check "the skill run is not flagged" 'python3 -c "import json,sys; sys.exit(bool(json.load(open(\"$d/skill/run-1/meta.json\"))[\"leaks\"]))"' "$(cat "$d/skill/run-1/meta.json")"
check "transcript.md and reply.md are written" 'grep -q "tool Edit" "$d/skill/run-1/transcript.md" && [ "$(cat "$d/skill/run-1/reply.md")" = Done. ]' "$(cat "$d/skill/run-1/transcript.md")"
check "run.json records the CLI version" 'grep -q "9.9.9 (Fake Code)" "$d/run.json"' "$(cat "$d/run.json")"
key=$(python3 -c "import json; print(json.load(open('$d/.keys/skill-run-1.json'))['original_pr'])")
other=$([ "$key" = A ] && echo B || echo A)
check "the key's side holds the PR, the other the run" 'cmp -s "$d/skill/run-1/compare/$key/changes.diff" "$d/reference/changes.diff" && cmp -s "$d/skill/run-1/compare/$other/changes.diff" "$d/skill/run-1/changes.diff"' "key=$key"
check "nothing the graders read names the PR's side" '! grep -rq original_pr "$d/skill/run-1" "$d/plain/run-1"' "found"

echo "summarize"
echo "{\"winner\": \"$other\"}" > "$d/skill/run-1/compare/comparison.json"
echo "{\"winner\": \"TIE\"}" > "$d/plain/run-1/compare/comparison.json"
echo '{"expectations":[{"text":"a","passed":true},{"text":"b","passed":false}]}' > "$d/skill/run-1/grading.json"
echo '{"expectations":[{"text":"a","passed":true},{"text":"b","passed":true}]}' > "$d/reference/grading.json"
s=$(python3 "$REPLAY" summarize "$d")
check "a row for the original PR" 'echo "$s" | grep -qF "| original PR | 1/1 | 1/1 | 2/2 |"' "$s"
check "the skill row: tests, checks, rubric, a win" 'echo "$s" | grep -qF "| skill | 1/1 | 1/1 | 1/2 | 1/0/0 | 0.50 | 3 | 2.0 | 0 |"' "$s"
check "the plain row: failed tests, a tie, a leak" 'echo "$s" | grep -qF "| plain | 0/1 | 1/1 | – | 0/1/0 |" && echo "$s" | grep -qE "\| plain .*\| 1 \|$"' "$s"
check "warns about the leak and the empty change" 'echo "$s" | grep -q "plain/run-1 may have seen the PR" && echo "$s" | grep -q "plain/run-1 changed nothing"' "$s"
check "names the PR and the CLI" 'echo "$s" | grep -q "PR #7, merged 2026-01-02. 9.9.9 (Fake Code). 1 run(s) per arm."' "$s"

echo "skill-ref"
python3 "$REPLAY" run "$task" "$WORK/r" --model m --runs 1 --arms skill --skill-ref "$v2" >/dev/null 2>&1
d="$WORK/r/app-pr7/$(date +%F)-m"
check "the arm is named skill@REF" '[ -f "$d/skill@$v2/run-1/meta.json" ] && [ ! -e "$d/plain" ]' "$(ls "$d")"
check "it loads the skill at that ref" 'grep -q "\"ref\": \"$v2\"" "$d/skill@$v2/run-1/meta.json"' "$(cat "$d/skill@$v2/run-1/meta.json")"
check "summarize finds the arm" 'python3 "$REPLAY" summarize "$d" | grep -qF "| skill@$v2 | 1/1 |"' "$(python3 "$REPLAY" summarize "$d")"

echo "bad tasks"
sed '/^test_command/d' "$task" > "$repo/.skills-replay/app-pr7/no-test.yaml"
check "a task without test_command is refused" '! python3 "$REPLAY" run "$repo/.skills-replay/app-pr7/no-test.yaml" "$WORK/x" --model m --runs 0 >/dev/null 2>&1' "accepted"
sed "s/^head: .*/head: 0123456789abcdef0123456789abcdef01234567/" "$task" > "$repo/.skills-replay/app-pr7/no-head.yaml"
out=$(python3 "$REPLAY" run "$repo/.skills-replay/app-pr7/no-head.yaml" "$WORK/x" --model m --runs 0 2>&1); code=$?
check "a head that isn't fetched is refused" '[ "$code" -ne 0 ] && echo "$out" | grep -q "no commit .* (head). Fetch it first"' "$out"
sed "s/^head: .*/head: $base/" "$task" > "$repo/.skills-replay/app-pr7/no-op.yaml"
sed -i 's/^test_command: .*/test_command: "true"/' "$repo/.skills-replay/app-pr7/no-op.yaml"
python3 "$REPLAY" run "$repo/.skills-replay/app-pr7/no-op.yaml" "$WORK/y" --model m --runs 0 >/dev/null 2>&1
check "warns when the hidden tests pass on the base" 'python3 "$REPLAY" summarize "$WORK/y/app-pr7/"* | grep -q "already pass on the base"' "$(python3 "$REPLAY" summarize "$WORK/y/app-pr7/"*)"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
