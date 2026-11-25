"""Check that every eval case of a skill is in the shape `claude plugin eval` loads.

    python3 check-evals.py <skill-dir>

For a skill's tests/evals.test.sh, which runs it and then checks its own
fixtures. Prints one line per check, `ok|<name>` or `bad|<name>|<why>`, and
exits 1 if any is bad. A case passes when:

  - its folder name is a valid case name, and not one the CLI keeps for itself
  - prompt.md has a settings block with only known keys, and a prompt; for a
    user-invoked skill, the prompt invokes it: /<name>, alone or with arguments
  - case.yaml has schema_version "1.1" as a string, its folder's name, an
    expected_outcome, and the scaffold_script it names, if it names one
  - graders/ holds at least one NN-few-words.md, each with a type, a numeric
    weight, and a statement
"""
import re
import sys
from pathlib import Path

import yaml

SETTINGS = {"tags", "max_turns", "timeout_seconds", "allowed_tools"}
RESERVED = {"results", "mocks", "node_modules", "files", "true", "false", "null"}
NOT_CASES = {"results", "mocks", "benchmarks"}


def front(path):
    m = re.match(r"---\n(.*?)\n---\n(.*)", path.read_text(), re.S)
    return (yaml.safe_load(m.group(1)), m.group(2).strip()) if m else (None, path.read_text().strip())


def check(case, skill, user_invoked):
    problems = []
    if not re.fullmatch(r"[a-z][a-z0-9-]*", case.name) or case.name in RESERVED:
        problems.append("bad case name")

    settings, prompt = front(case / "prompt.md") if (case / "prompt.md").is_file() else (None, "")
    if not isinstance(settings, dict):
        problems.append("prompt.md has no settings block")
    elif set(settings) - SETTINGS:
        problems.append(f"unknown settings {sorted(set(settings) - SETTINGS)}")
    if not prompt:
        problems.append("prompt.md has no prompt")
    elif user_invoked and prompt != f"/{skill}" and not prompt.startswith(f"/{skill} "):
        problems.append(f"prompt doesn't invoke /{skill}")

    c = yaml.safe_load((case / "case.yaml").read_text()) if (case / "case.yaml").is_file() else None
    c = c if isinstance(c, dict) else {}
    if c.get("schema_version") != "1.1":
        problems.append('schema_version isn\'t the string "1.1"')
    if c.get("name") != case.name:
        problems.append(f"case.yaml name is {c.get('name')!r}")
    if not (isinstance(c.get("expected_outcome"), str) and c["expected_outcome"].strip()):
        problems.append("no expected_outcome")
    script = (c.get("context") or {}).get("scaffold_script")
    if script and not (case / script).is_file():
        problems.append(f"no {script} beside case.yaml")

    graders = sorted((case / "graders").glob("*.md"))
    if not graders:
        problems.append("no graders")
    for g in graders:
        meta, body = front(g)
        if not re.fullmatch(r"\d\d-[a-z0-9-]+\.md", g.name):
            problems.append(f"{g.name}: not NN-few-words.md")
        if not (isinstance(meta, dict) and isinstance(meta.get("type"), str)
                and isinstance(meta.get("weight"), (int, float)) and not isinstance(meta.get("weight"), bool)):
            problems.append(f"{g.name}: header needs a type and a numeric weight")
        if not body or "TODO" in body:
            problems.append(f"{g.name}: no statement")
    return problems


def main(argv):
    if len(argv) != 1:
        sys.exit(__doc__)
    skill_dir = Path(argv[0]).resolve()
    fm, _ = front(skill_dir / "SKILL.md")
    user_invoked = isinstance(fm, dict) and fm.get("disable-model-invocation") is True
    evals = skill_dir / "tests" / "evals"
    cases = sorted(p for p in evals.iterdir() if p.is_dir() and p.name not in NOT_CASES) if evals.is_dir() else []
    bad = 0
    print("ok|at least one case" if cases else "bad|at least one case|no case folders")
    bad += not cases
    for case in cases:
        problems = check(case, skill_dir.name, user_invoked)
        print(f"ok|{case.name}: loads" if not problems else f"bad|{case.name}: loads|{'; '.join(problems)}")
        bad += bool(problems)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main(sys.argv[1:])
