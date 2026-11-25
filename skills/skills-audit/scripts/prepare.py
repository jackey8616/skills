"""Set up one iteration of eval runs for a skill.

    python3 prepare.py <skill-dir> <base-dir> <iteration> [--old <snapshot-dir>]

<skill-dir>/tests/evals/ holds the cases, one folder each, in the layout
`claude plugin eval` reads. <base-dir> is outside any repository (your
scratchpad). This writes:

  <base>/<skill>-workspace/            skill-creator's workspace layout
    skill-snapshot/                    the skill as first audited, no tests/
    iteration-<N>/
      runs.json                        every run below, for building prompts
      <case>/eval_metadata.json        prompt and assertions, for the viewer
      <case>/<config>/run.json         where that run works, its start state,
                                       and the exact prompt to give it
  <base>/s/<id>/<skill>/               the skill a run reads, without tests/
  <base>/r/<id>/project/               the directory a run works in, built by
                                       the case's scaffold_script if it has one

Configs: with_skill is <skill-dir> as it is now; old_skill, with --old, is
that snapshot. Run and skill paths are random ids, so nothing a run can see
names the case or what it expects. Each run's `executor_prompt` is the whole
prompt for its subagent, to send as it is. Prints runs.json.
"""
import json
import re
import secrets
import shutil
import subprocess
import sys
from pathlib import Path

import yaml


def front(path):
    m = re.match(r"---\n(.*?)\n---\n(.*)", path.read_text(), re.S)
    return (yaml.safe_load(m.group(1)) or {}, m.group(2).strip()) if m else ({}, path.read_text().strip())


def files(project):
    return sorted(str(f.relative_to(project)) for f in project.rglob("*")
                  if f.is_file() and ".git" not in f.relative_to(project).parts)


def executor_prompt(run):
    lines = [
        "Execute this task:",
        f"- Skill path: {run['skill_path']} — read its SKILL.md and follow it.",
        f"- Task: the user typed this in the project at {run['project']}:",
        "",
        *("  " + line if line else "" for line in run["prompt"].splitlines()),
        "",
    ]
    if run["arguments"] is not None:
        lines.append(f"  So `$ARGUMENTS` in the skill is: {run['arguments']}" if run["arguments"]
                     else "  So `$ARGUMENTS` in the skill is empty.")
    lines += [
        "  That directory is the project you're working in. Your shell doesn't start there, so cd into it (or use absolute paths) in each command.",
        f"- Temp directory, for anything the skill lets you write outside the project: {run['tmp']}",
        f"- Save outputs to: {run['reply']} — your final reply to the user, exactly as you would give it. Also return it as your final message.",
    ]
    return "\n".join(lines)


def copy_skill(src, dest):
    if dest.exists():
        shutil.rmtree(dest)
    shutil.copytree(src, dest, ignore=shutil.ignore_patterns("tests"))


def main(argv):
    old = None
    if "--old" in argv:
        i = argv.index("--old")
        old = Path(argv[i + 1]).resolve()
        argv = argv[:i] + argv[i + 2:]
    if len(argv) != 3:
        sys.exit(__doc__)
    skill_dir, base, iteration = Path(argv[0]).resolve(), Path(argv[1]).resolve(), int(argv[2])
    name = skill_dir.name
    evals = skill_dir / "tests" / "evals"
    cases = sorted(p for p in evals.iterdir() if (p / "case.yaml").is_file()) if evals.is_dir() else []
    if not cases:
        sys.exit(f"no cases in {evals}")

    ws = base / f"{name}-workspace"
    snapshot = ws / "skill-snapshot"
    if not snapshot.exists():
        copy_skill(skill_dir, snapshot)
    it = ws / f"iteration-{iteration}"
    if it.exists():
        sys.exit(f"{it} exists; pick the next iteration number")

    configs = {"with_skill": skill_dir}
    if old:
        configs["old_skill"] = old
    skill_copies = {}
    for config, src in configs.items():
        dest = base / "s" / secrets.token_hex(4) / name
        copy_skill(src, dest)
        skill_copies[config] = dest

    runs = []
    for case in cases:
        meta = yaml.safe_load((case / "case.yaml").read_text()) or {}
        _, prompt = front(case / "prompt.md")
        assertions = [" ".join(front(g)[1].split()) for g in sorted((case / "graders").glob("*.md"))]
        (it / case.name).mkdir(parents=True)
        (it / case.name / "eval_metadata.json").write_text(json.dumps(
            {"eval_name": case.name, "prompt": prompt, "assertions": assertions}, indent=2) + "\n")
        invoke = f"/{name}"
        arguments = prompt[len(invoke):].strip() if prompt == invoke or prompt.startswith(invoke + " ") else None
        scaffold = (meta.get("context") or {}).get("scaffold_script")

        for config in configs:
            run_dir = base / "r" / secrets.token_hex(4)
            project = run_dir / "project"
            project.mkdir(parents=True)
            (run_dir / "tmp").mkdir()
            if scaffold:
                subprocess.run(["bash", str(case / scaffold)], cwd=project, check=True,
                               stdout=subprocess.DEVNULL)
            head = subprocess.run(["git", "-C", str(project), "rev-parse", "HEAD"],
                                  capture_output=True, text=True)
            run = {
                "case": case.name,
                "config": config,
                "skill_path": str(skill_copies[config]),
                "run_dir": str(run_dir),
                "project": str(project),
                "reply": str(run_dir / "reply.md"),
                "tmp": str(run_dir / "tmp"),
                "prompt": prompt,
                "arguments": arguments,
                "start_head": head.stdout.strip() if head.returncode == 0 else None,
                "start_files": files(project),
            }
            run["executor_prompt"] = executor_prompt(run)
            (it / case.name / config).mkdir()
            (it / case.name / config / "run.json").write_text(json.dumps(run, indent=2) + "\n")
            runs.append(run)

    (it / "runs.json").write_text(json.dumps(runs, indent=2) + "\n")
    print(json.dumps(runs, indent=2))


if __name__ == "__main__":
    main(sys.argv[1:])
