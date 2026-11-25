#!/usr/bin/env bash
# Offline checks for the behaviour evals in tests/evals/. The evals are billed
# model runs (see CLAUDE.md); this runs no model. deepen works on text alone,
# so the cases have no fixtures: this checks each case is in the shape
# `claude plugin eval` loads, and that its prompt is the one its case is
# about (no arguments for the empty-arguments case, a prompt for the rest).
#
#   bash skills/deepen/tests/evals.test.sh
set -uo pipefail

TESTS="$(cd "$(dirname "$0")" && pwd)"
EVALS="$TESTS/evals"
SKILL="$(basename "$(dirname "$TESTS")")"

pass=0
fail=0
ok()   { pass=$((pass + 1)); echo "  ok   $1"; }
bad()  { fail=$((fail + 1)); echo "  FAIL $1 — got: $2"; }

while IFS='|' read -r verdict name why; do
  if [ "$verdict" = ok ]; then ok "$name"; else bad "$name" "$why"; fi
done < <(python3 - "$EVALS" "$SKILL" <<'EOF'
import re, sys
from pathlib import Path
import yaml

evals, skill = Path(sys.argv[1]), sys.argv[2]
SETTINGS = {"tags", "max_turns", "timeout_seconds", "allowed_tools"}
RESERVED = {"results", "mocks", "node_modules", "files", "true", "false", "null"}
NEEDS_NO_ARGUMENTS = {"empty-arguments-asks"}

def front(path):
    m = re.match(r"---\n(.*?)\n---\n(.*)", path.read_text(), re.S)
    return (yaml.safe_load(m.group(1)), m.group(2).strip()) if m else (None, path.read_text())

def report(name, problems):
    print(f"ok|{name}" if not problems else f"bad|{name}|{'; '.join(problems)}")

cases = sorted(p for p in evals.iterdir() if p.is_dir() and p.name not in ("results", "benchmarks"))
report("at least one case", [] if cases else ["no case folders"])
for case in cases:
    n, problems = case.name, []
    if not re.fullmatch(r"[a-z][a-z0-9-]*", n) or n in RESERVED:
        problems.append("bad case name")

    settings, prompt = front(case / "prompt.md") if (case / "prompt.md").is_file() else (None, "")
    if not isinstance(settings, dict):
        problems.append("prompt.md has no settings block")
    elif set(settings) - SETTINGS:
        problems.append(f"unknown settings {sorted(set(settings) - SETTINGS)}")
    if n in NEEDS_NO_ARGUMENTS:
        if prompt != f"/{skill}":
            problems.append(f"prompt isn't /{skill} alone: {prompt!r}")
    elif not prompt.startswith(f"/{skill} ") or not prompt[len(skill) + 2:].strip():
        problems.append(f"prompt doesn't invoke /{skill} with a prompt to deepen")

    c = yaml.safe_load((case / "case.yaml").read_text()) if (case / "case.yaml").is_file() else {}
    if c.get("schema_version") != "1.1":
        problems.append("schema_version isn't the string \"1.1\"")
    if c.get("name") != n:
        problems.append(f"case.yaml name is {c.get('name')!r}")
    if not (isinstance(c.get("expected_outcome"), str) and c["expected_outcome"].strip()):
        problems.append("no expected_outcome")
    script = (c.get("context") or {}).get("scaffold_script")
    if script and not (case / script).is_file():
        problems.append(f"scaffold_script {script} is missing")

    graders = sorted((case / "graders").glob("*.md"))
    if not graders:
        problems.append("no graders")
    for g in graders:
        meta, body = front(g)
        if not re.fullmatch(r"\d\d-[a-z0-9-]+\.md", g.name):
            problems.append(f"{g.name}: not NN-few-words.md")
        if not (isinstance(meta, dict) and meta.get("type") == "llm" and meta.get("focus") == "trace" and meta.get("weight") == 1):
            problems.append(f"{g.name}: header isn't type llm, focus trace, weight 1")
        if not body or "TODO" in body:
            problems.append(f"{g.name}: no statement")
    report(f"{n}: loads, and its prompt fits the case", problems)
EOF
)

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
