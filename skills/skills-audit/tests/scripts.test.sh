#!/usr/bin/env bash
# Tests for skills/skills-audit/scripts/: prepare.py, collect.py, and
# find-skill-creator.sh. Offline: a made-up skill with two eval cases, and a
# made-up skill-creator under a throwaway $HOME.
#
#   bash skills/skills-audit/tests/scripts.test.sh
set -uo pipefail

SCRIPTS="$(cd "$(dirname "$0")/../scripts" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0
ok()   { pass=$((pass + 1)); echo "  ok   $1"; }
bad()  { fail=$((fail + 1)); echo "  FAIL $1 — got: $2"; }
check() { if eval "$2"; then ok "$1"; else bad "$1" "$3"; fi; }

# A user-invoked skill `widget` with a case that builds a git repo, one that
# invokes it with no arguments, and one whose prompt doesn't name it.
skill="$WORK/skills/widget"
mkdir -p "$skill/agents" "$skill/tests/evals/repo-case/graders" "$skill/tests/evals/plain-case/graders" "$skill/tests/evals/free-case/graders"
printf -- '---\nname: widget\ndescription: Widget.\n---\nBody\n' > "$skill/SKILL.md"
echo 'interface: {}' > "$skill/agents/openai.yaml"
echo 'true' > "$skill/tests/scripts.test.sh"
for c in repo-case plain-case free-case; do
  printf -- '---\nmax_turns: 5\n---\n\n/widget do the %s thing\n' "$c" > "$skill/tests/evals/$c/prompt.md"
  printf -- '---\ntype: llm\nfocus: trace\nweight: 1\n---\n\nThe reply says\n%s.\n' "$c" > "$skill/tests/evals/$c/graders/01-says.md"
done
printf 'schema_version: "1.1"\nname: repo-case\nexpected_outcome: |\n  x\ncontext:\n  scaffold_script: place-files.sh\n' > "$skill/tests/evals/repo-case/case.yaml"
printf 'schema_version: "1.1"\nname: plain-case\nexpected_outcome: |\n  x\n' > "$skill/tests/evals/plain-case/case.yaml"
printf -- '---\nmax_turns: 5\n---\n\n/widget\n' > "$skill/tests/evals/plain-case/prompt.md"
printf 'schema_version: "1.1"\nname: free-case\nexpected_outcome: |\n  x\n' > "$skill/tests/evals/free-case/case.yaml"
printf -- '---\nmax_turns: 5\n---\n\nPlease tidy\nthe widgets.\n' > "$skill/tests/evals/free-case/prompt.md"
cat > "$skill/tests/evals/repo-case/place-files.sh" <<'EOF'
#!/usr/bin/env bash
set -eu
git init -q -b main .
echo hi > a.txt
git add -A && git -c user.name=f -c user.email=f@f commit -qm base
EOF
mkdir -p "$skill/tests/evals/results"
old="$WORK/old/widget"
mkdir -p "$old"
printf -- '---\nname: widget\ndescription: Old.\n---\nOld body\n' > "$old/SKILL.md"

echo "prepare.py"
base="$WORK/base"
out="$(python3 "$SCRIPTS/prepare.py" "$skill" "$base" 1 --old "$old" 2>&1)"; rc=$?
ws="$base/widget-workspace"
it="$ws/iteration-1"
check "exits 0" '[ "$rc" -eq 0 ]' "exit $rc: $out"
runs="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$it/runs.json" 2>&1)"
check "one run per case and config, results/ skipped" '[ "$runs" = 6 ]' "$runs runs"
check "prints runs.json" '[ "$(printf "%s" "$out" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")" = 6 ]' "$out"
field() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$it/$1/$2/run.json" "$3"; }
check "snapshot of the skill, without tests/" '[ -f "$ws/skill-snapshot/SKILL.md" ] && [ ! -e "$ws/skill-snapshot/tests" ]' "$(ls -A "$ws/skill-snapshot")"
new_copy="$(field repo-case with_skill skill_path)"
old_copy="$(field repo-case old_skill skill_path)"
check "with_skill reads a copy of the skill, without tests/" \
  'grep -q "^Body$" "$new_copy/SKILL.md" && [ ! -e "$new_copy/tests" ] && [ "$(basename "$new_copy")" = widget ]' "$new_copy"
check "old_skill reads a copy of the snapshot given" 'grep -q "^Old body$" "$old_copy/SKILL.md"' "$old_copy"
project="$(field repo-case with_skill project)"
check "the scaffold built the project" '[ "$(git -C "$project" log --format=%s)" = base ]' "$(ls -A "$project")"
check "start HEAD is recorded" '[ "$(field repo-case with_skill start_head)" = "$(git -C "$project" rev-parse HEAD)" ]' "$(field repo-case with_skill start_head)"
check "a case with no scaffold gets an empty project and no HEAD" \
  '[ -z "$(ls -A "$(field plain-case with_skill project)")" ] && [ "$(field plain-case with_skill start_head)" = None ]' "$(field plain-case with_skill start_head)"
check "each config of a case gets its own project" '[ "$project" != "$(field repo-case old_skill project)" ]' "$project"
check "arguments are the prompt after /widget" '[ "$(field repo-case with_skill arguments)" = "do the repo-case thing" ]' "$(field repo-case with_skill arguments)"
paths="$(python3 -c 'import json,sys; [print(r[k]) for r in json.load(open(sys.argv[1])) for k in ("skill_path","run_dir","project","reply","tmp")]' "$it/runs.json")"
check "no path a run sees names its case or the workspace" '! printf "%s" "$paths" | grep -Eq "repo-case|plain-case|free-case|workspace|iteration"' "$paths"
check "start files list the scaffold's files, not .git" '[ "$(python3 -c "import json,sys; print(\" \".join(json.load(open(sys.argv[1]))[\"start_files\"]))" "$it/repo-case/with_skill/run.json")" = "a.txt" ]' "$(cat "$it/repo-case/with_skill/run.json")"
eprompt() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["executor_prompt"])' "$it/$1/with_skill/run.json"; }
p="$(eprompt repo-case)"
check "the executor prompt names the run's own paths and the arguments" \
  'printf "%s\n" "$p" | grep -qxF -- "- Skill path: $new_copy — read its SKILL.md and follow it." && printf "%s\n" "$p" | grep -qxF "  /widget do the repo-case thing" && printf "%s\n" "$p" | grep -qxF "  So \`\$ARGUMENTS\` in the skill is: do the repo-case thing" && printf "%s\n" "$p" | grep -qF "Save outputs to: $(field repo-case with_skill reply)"' "$p"
p="$(eprompt plain-case)"
check "with no arguments, the executor prompt says \$ARGUMENTS is empty" 'printf "%s\n" "$p" | grep -qxF "  So \`\$ARGUMENTS\` in the skill is empty."' "$p"
p="$(eprompt free-case)"
check "a prompt that doesn't name the skill has no \$ARGUMENTS line, and keeps its lines" \
  '! printf "%s\n" "$p" | grep -q "ARGUMENTS" && printf "%s\n" "$p" | grep -qxF "  Please tidy" && printf "%s\n" "$p" | grep -qxF "  the widgets."' "$p"
meta="$(python3 -c 'import json,sys; m=json.load(open(sys.argv[1])); print(m["eval_name"], "|", m["prompt"], "|", m["assertions"])' "$it/repo-case/eval_metadata.json")"
check "eval_metadata.json has name, prompt, and assertions joined to one line" \
  "[ \"\$meta\" = \"repo-case | /widget do the repo-case thing | ['The reply says repo-case.']\" ]" "$meta"
out="$(python3 "$SCRIPTS/prepare.py" "$skill" "$base" 1 2>&1)"; rc=$?
check "refuses an iteration that exists" '[ "$rc" -ne 0 ] && printf "%s" "$out" | grep -q "pick the next iteration"' "exit $rc: $out"

echo "collect.py"
run_dir="$(field repo-case with_skill run_dir)"
echo "the reply" > "$run_dir/reply.md"
echo new > "$project/left.txt"
cat > "$WORK/t.jsonl" <<'EOF'
{"type":"user","message":{"role":"user","content":"go"}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls -la"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","content":[{"type":"text","text":"a.txt"}]}]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/x/a.txt"}}]}}
not json
{"type":"assistant","message":{"content":[{"type":"text","text":"Done."}]}}
EOF
out="$(python3 "$SCRIPTS/collect.py" "$it" repo-case with_skill --tokens 1234 --ms 5600 --transcript "$WORK/t.jsonl" 2>&1)"; rc=$?
d="$it/repo-case/with_skill"
check "exits 0 and summarises" '[ "$rc" -eq 0 ] && [ "$out" = "repo-case/with_skill: reply found, HEAD unchanged, 2 tool calls" ]' "exit $rc: $out"
check "copies the reply" '[ "$(cat "$d/outputs/reply.md")" = "the reply" ]' "$(cat "$d/outputs/reply.md" 2>&1)"
check "repo-state shows what the run left" 'grep -q "^?? left.txt$" "$d/outputs/repo-state.md" && grep -q "(unchanged)" "$d/outputs/repo-state.md"' "$(cat "$d/outputs/repo-state.md" 2>&1)"
check "transcript lists tool calls in order, with results" \
  'grep -q "^## 1. Bash$" "$d/transcript.md" && grep -q "^ls -la$" "$d/transcript.md" && grep -q "^a.txt$" "$d/transcript.md" && grep -q "^## 2. Read$" "$d/transcript.md" && grep -q "^> Done.$" "$d/transcript.md"' "$(cat "$d/transcript.md" 2>&1)"
check "timing.json from the notice" \
  '[ "$(python3 -c "import json,sys; t=json.load(open(sys.argv[1])); print(t[\"total_tokens\"], t[\"duration_ms\"], t[\"total_duration_seconds\"])" "$d/timing.json")" = "1234 5600 5.6" ]' "$(cat "$d/timing.json" 2>&1)"
old_project="$(field repo-case old_skill project)"
git -C "$old_project" -c user.name=x -c user.email=x@x commit -q --allow-empty -m oops
out="$(python3 "$SCRIPTS/collect.py" "$it" repo-case old_skill --tokens 1 --ms 1 2>&1)"
check "flags a moved HEAD, a missing reply, and no transcript" \
  '[ "$out" = "repo-case/old_skill: reply MISSING, HEAD CHANGED, no transcript" ] && grep -q "(CHANGED)" "$it/repo-case/old_skill/outputs/repo-state.md"' "$out"
out="$(python3 "$SCRIPTS/collect.py" "$it" plain-case with_skill --tokens 1 --ms 1 2>&1)"
check "a project that isn't a repo gets project-state, not repo-state" \
  '[ "$out" = "plain-case/with_skill: reply MISSING, files unchanged, no transcript" ] && [ ! -e "$it/plain-case/with_skill/outputs/repo-state.md" ] && grep -q "^- Created: none$" "$it/plain-case/with_skill/outputs/project-state.md"' "$out"
mkdir -p "$(field free-case with_skill project)/sub" && echo x > "$(field free-case with_skill project)/sub/made.py"
out="$(python3 "$SCRIPTS/collect.py" "$it" free-case with_skill --tokens 1 --ms 1 2>&1)"
check "project-state names a file the run created" \
  '[ "$out" = "free-case/with_skill: reply MISSING, files CHANGED, no transcript" ] && grep -qF -- "- Created: \`sub/made.py\`" "$it/free-case/with_skill/outputs/project-state.md"' "$out"

echo "check-evals.py"
# ce <skill-dir> — check-evals.py's lines in $CE, its exit status in $RC.
ce() { RC=0; CE="$(python3 "$SCRIPTS/check-evals.py" "$1" 2>&1)" || RC=$?; }
mkdir -p "$skill/tests/evals/benchmarks"
ce "$skill"
check "a model-invoked skill's cases all load, results/ and benchmarks/ skipped" \
  '[ "$RC" -eq 0 ] && [ "$(printf "%s\n" "$CE" | grep -c "^ok|")" = 4 ] && ! printf "%s" "$CE" | grep -q "^bad"' "exit $RC: $CE"
# bad_after <what> <setup> <want> — copy the skill, break it with <setup>
# (run inside the copy), and check exactly one bad line, containing <want>.
bad_after() {
  local copy="$WORK/ce-$pass-$fail/widget"
  mkdir -p "$(dirname "$copy")" && cp -R "$skill" "$copy"
  (cd "$copy" && eval "$2")
  ce "$copy"
  check "$1" '[ "$RC" -eq 1 ] && [ "$(printf "%s\n" "$CE" | grep -c "^bad|")" = 1 ] && printf "%s\n" "$CE" | grep "^bad|" | grep -qF "$3"' "exit $RC: $CE"
}
bad_after "a user-invoked skill's prompt must invoke it" \
  "printf -- '---\nname: widget\ndescription: W.\ndisable-model-invocation: true\n---\n' > SKILL.md" \
  "free-case: loads|prompt doesn't invoke /widget"
bad_after "an unknown setting" "sed -i.bak 's/^max_turns: 5/runs: 1/' tests/evals/plain-case/prompt.md" "unknown settings ['runs']"
bad_after "an unquoted schema_version" "sed -i.bak 's/\"1.1\"/1.1/' tests/evals/free-case/case.yaml" "schema_version"
bad_after "a scaffold that isn't there" "rm tests/evals/repo-case/place-files.sh" "no place-files.sh beside case.yaml"
bad_after "a grader with no weight" "sed -i.bak '/^weight:/d' tests/evals/repo-case/graders/01-says.md" "needs a type and a numeric weight"
bad_after "a grader with no statement" "printf -- '---\ntype: llm\nweight: 1\n---\n' > tests/evals/repo-case/graders/01-says.md" "no statement"
bad_after "a case named for something the CLI keeps" "mv tests/evals/plain-case tests/evals/files && sed -i.bak 's/plain-case/files/' tests/evals/files/case.yaml" "bad case name"
mkdir -p "$WORK/none/widget/tests/evals" && cp "$skill/SKILL.md" "$WORK/none/widget/"
ce "$WORK/none/widget"
check "no cases is bad, exit 1" '[ "$RC" -eq 1 ] && [ "$CE" = "bad|at least one case|no case folders" ]' "exit $RC: $CE"

echo "find-skill-creator.sh"
fake_home="$WORK/home"
sc="$fake_home/.claude/skills/x/skill-creator"
mkdir -p "$sc/agents" "$sc/scripts" "$sc/eval-viewer"
find_sc() { SKILL_CREATOR_SEARCH="$WORK/empty:$fake_home/.claude/skills" bash "$SCRIPTS/find-skill-creator.sh" 2>&1; }
touch "$sc/agents/grader.md" "$sc/scripts/aggregate_benchmark.py"
rc=0; got="$(find_sc)" || rc=$?
check "an incomplete skill-creator isn't used" '[ "$rc" -eq 1 ] && [ -z "$got" ]' "exit $rc: $got"
touch "$sc/eval-viewer/generate_review.py"
got="$(find_sc)"
check "finds a complete one, skipping a missing search root" '[ "$got" = "$(cd "$sc" && pwd)" ]' "$got"
got="$(SKILL_CREATOR="$sc" SKILL_CREATOR_SEARCH="$WORK/empty" bash "$SCRIPTS/find-skill-creator.sh")"
check "\$SKILL_CREATOR wins" '[ "$got" = "$(cd "$sc" && pwd)" ]' "$got"
rc=0; SKILL_CREATOR="$WORK/nowhere" bash "$SCRIPTS/find-skill-creator.sh" >/dev/null || rc=$?
check "a bad \$SKILL_CREATOR exits 1" '[ "$rc" -eq 1 ]' "exit $rc"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
