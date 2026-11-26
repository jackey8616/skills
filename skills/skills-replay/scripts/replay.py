"""Replay a merged PR's task on a model, with and without skills, and score it.

    python3 replay.py doctor [--live]
    python3 replay.py run <task.yaml> <base-dir> --model <m> [--runs N]
                          [--arms plain,skills] [--skills-dir DIR] [-j N]
                          [--repo <path>]
    python3 replay.py summarize <label-dir> [<label-dir>...]

<task.yaml> describes one PR (references/task-file.md has the fields). It
usually sits at <repo>/.skills-replay/<task-id>/task.yaml, and <repo> is the
git top level of that file unless --repo says otherwise. <base-dir> is outside
any repository (your scratchpad).

`run` writes <base>/<task-id>/<YYYY-MM-DD>-<model>/ (the label dir):

  run.json                    the model, arms, CLI version, the skills loaded
  base-check.json             the PR's hidden tests run on the untouched base:
                              they should fail, or the task can't tell a fix
  reference/                  the original PR applied to the base
    changes.diff, checks.json
  <arm>/run-<k>/              one model run
    meta.json                 cost, turns, duration, how it ended, leak hits
    transcript.jsonl          the CLI's stream-json output, as it came
    transcript.md             the same, trimmed for graders
    reply.md                  the run's final message
    changes.diff              everything it changed, against the start commit
    checks.json               hidden tests and checks, run in a copy
    compare/A/, compare/B/    this run's diff and the PR's, in random order
  .keys/<arm>-<k>.json        which of A and B is the PR; graders never read it

Every run starts from a fresh copy of the base commit: one commit of history,
no remote, no .skills-replay/, .claude/skills/ or .agents/skills/. Its
CLAUDE_CONFIG_DIR is new, and no MCP server starts. `plain` gets no skills
and the task's plain_prompt: the model on its own. `skills` gets a copy of
every skill the user has installed (--skills-dir, default ~/.claude/skills)
and the prompt as it was typed: the model as the user works with it. The
task file names no skill: the comparison is the model with its skills
against the model without, not one skill against none. run.json records the
skills' names and a digest of their files, so two dates can tell whether the
set changed between them.

`summarize` reads label dirs, with any grading.json and compare/comparison.json
the graders wrote, and prints a Markdown report. Set CLAUDE_BIN to use another
claude binary (the tests use a fake one).
"""
import argparse
import concurrent.futures
import datetime
import hashlib
import json
import os
import random
import re
import secrets
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    import yaml
except ImportError:
    print("PyYAML not found. Install it: pip install pyyaml", file=sys.stderr)
    sys.exit(2)

STRIP = [".skills-replay", ".claude/skills", ".agents/skills"]
ALLOWED = ["Bash", "Read", "Edit", "Write", "Glob", "Grep", "Skill", "Agent", "TodoWrite", "NotebookEdit"]
DISALLOWED = ["WebFetch", "WebSearch", "Bash(gh:*)", "Bash(git fetch:*)", "Bash(git pull:*)",
              "Bash(git clone:*)", "Bash(git remote:*)"]
SECRET_ENV = ["GH_TOKEN", "GITHUB_TOKEN", "GH_ENTERPRISE_TOKEN", "CLAUDE_CODE_SYNC_SKILLS"]
CHECK_TIMEOUT = 900


def sh(cmd, cwd=None, check=True, **kw):
    return subprocess.run(cmd, cwd=cwd, check=check, text=True, capture_output=True, **kw)


def git(repo, *args, **kw):
    return sh(["git", "-C", str(repo), *args], **kw)


def slug(text):
    return re.sub(r"[^a-z0-9.]+", "-", text.lower()).strip("-")


def load_task(path, repo=None):
    path = Path(path).resolve()
    task = yaml.safe_load(path.read_text()) or {}
    for key in ("id", "base", "head", "prompt", "test_command"):
        if not task.get(key):
            sys.exit(f"{path}: `{key}` is required")
    repo = Path(repo).resolve() if repo else Path(git(path.parent, "rev-parse", "--show-toplevel").stdout.strip())
    for key in ("base", "head"):
        if git(repo, "cat-file", "-e", f"{task[key]}^{{commit}}", check=False).returncode:
            sys.exit(f"{repo}: no commit {task[key]} ({key}). Fetch it first (references/task-file.md).")
    task.setdefault("plain_prompt", task["prompt"])
    task.setdefault("setup", [])
    task.setdefault("hidden_tests", [])
    task.setdefault("checks", [])
    task.setdefault("rubric", [])
    task.setdefault("max_turns", 80)
    task.setdefault("timeout_seconds", 1800)
    task.setdefault("leak_patterns", [])
    return task, repo


def snapshot(repo, task, dest):
    """A one-commit copy of the base, with setup run and committed. Returns the start sha."""
    dest.mkdir(parents=True)
    archive = subprocess.run(["git", "-C", str(repo), "archive", task["base"]], check=True, capture_output=True)
    subprocess.run(["tar", "-x", "-C", str(dest)], input=archive.stdout, check=True)
    for rel in STRIP:
        shutil.rmtree(dest / rel, ignore_errors=True)
        parent = (dest / rel).parent
        while parent != dest and parent.is_dir() and not any(parent.iterdir()):
            parent.rmdir()
            parent = parent.parent
    ident = ["-c", "user.name=replay", "-c", "user.email=replay@localhost", "-c", "commit.gpgsign=false"]
    env = {**os.environ, "GIT_AUTHOR_DATE": "2000-01-01T00:00:00Z", "GIT_COMMITTER_DATE": "2000-01-01T00:00:00Z"}
    git(dest, "init", "-q", "-b", "main")
    git(dest, "add", "-A")
    git(dest, *ident, "commit", "-qm", "base", "--allow-empty", env=env)
    for cmd in task["setup"]:
        r = sh(["bash", "-c", cmd], cwd=dest, check=False, timeout=CHECK_TIMEOUT)
        if r.returncode:
            raise RuntimeError(f"setup `{cmd}` failed:\n{r.stdout[-2000:]}{r.stderr[-2000:]}")
    git(dest, "add", "-A")
    if git(dest, "diff", "--cached", "--quiet", check=False).returncode:
        git(dest, *ident, "commit", "-qm", "setup", env=env)
    return git(dest, "rev-parse", "HEAD").stdout.strip()


def changes(project, start):
    git(project, "add", "-A")
    return git(project, "diff", "--cached", "--binary", start).stdout


def run_checks(repo, task, project):
    """Overlay the PR's hidden tests on a copy of project, then run the tests and checks."""
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp) / "w"
        shutil.copytree(project, work, symlinks=True)
        for rel in task["hidden_tests"]:
            target = work / rel
            shown = subprocess.run(["git", "-C", str(repo), "show", f"{task['head']}:{rel}"], capture_output=True)
            if shown.returncode:
                target.unlink(missing_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(shown.stdout)
        results = {"hidden_tests": one_check("hidden tests", task["test_command"], work), "checks": []}
        for c in task["checks"]:
            results["checks"].append(one_check(c["name"], c["run"], work))
    return results


def one_check(name, cmd, cwd):
    try:
        r = sh(["bash", "-c", cmd], cwd=cwd, check=False, timeout=CHECK_TIMEOUT)
        return {"name": name, "passed": r.returncode == 0, "exit": r.returncode,
                "tail": (r.stdout + r.stderr)[-3000:]}
    except subprocess.TimeoutExpired:
        return {"name": name, "passed": False, "exit": None, "tail": f"timed out after {CHECK_TIMEOUT}s"}


def digest(d):
    h = hashlib.sha256()
    for f in sorted(p for p in d.rglob("*") if p.is_file()):
        h.update(str(f.relative_to(d)).encode() + b"\0" + f.read_bytes() + b"\0")
    return h.hexdigest()[:12]


def skill_names(d):
    return sorted(str(f.parent.relative_to(d)) for f in d.rglob("SKILL.md"))


def config_dir(dest, skills_dir):
    """A new CLAUDE_CONFIG_DIR, holding a copy of skills_dir as its skills/ if given."""
    dest.mkdir(parents=True)
    if skills_dir:
        shutil.copytree(skills_dir, dest / "skills", ignore=shutil.ignore_patterns("tests"))
    else:
        (dest / "skills").mkdir()
    return skill_names(dest / "skills")


def blocks(event):
    msg = event.get("message")
    content = msg.get("content") if isinstance(msg, dict) else None
    return [b for b in content if isinstance(b, dict)] if isinstance(content, list) else []


def trim(events):
    out = []
    for e in events:
        for block in blocks(e):
            kind = block.get("type")
            if e.get("type") == "assistant" and kind == "text":
                out.append(f"**assistant:** {block['text']}\n")
            elif kind == "tool_use":
                out.append(f"**tool {block.get('name')}:** `{json.dumps(block.get('input'))[:1500]}`\n")
            elif kind == "tool_result":
                content = block.get("content")
                if isinstance(content, list):
                    content = "\n".join(c.get("text", "") for c in content if isinstance(c, dict))
                out.append(f"**result:**\n```\n{str(content)[:1500]}\n```\n")
        if e.get("type") == "result":
            out.append(f"**final ({e.get('subtype')}):** {e.get('result', '')}\n")
    return "\n".join(out)


def leaks(events, task):
    """Tool calls that ran and point at the PR itself (its commits, its page, the forge), and results that name it.

    A call the permission rules refused saw nothing, so it isn't a leak."""
    patterns = [task["head"][:7], f"pull/{task.get('pr', '-')}", r"\bgh (pr|api)\b", r"\bgit (fetch|log --all|reflog)\b",
                *task["leak_patterns"]]
    calls, refused, results = {}, set(), []
    for e in events:
        for block in blocks(e):
            if block.get("type") == "tool_use":
                calls[block.get("id")] = json.dumps(block.get("input"))
            elif block.get("type") == "tool_result":
                if block.get("is_error"):
                    refused.add(block.get("tool_use_id"))
                else:
                    results.append(json.dumps(block.get("content")))
    blob = "\n".join([c for i, c in calls.items() if i not in refused] + results)
    return sorted({p for p in patterns if p and re.search(p, blob)})


def one_run(repo, task, label_dir, base, arm, k, model, skills_dir):
    out = label_dir / arm / f"run-{k}"
    out.mkdir(parents=True)
    project = base / "p" / secrets.token_hex(6) / "project"
    cfg = base / "c" / secrets.token_hex(6)
    start = snapshot(repo, task, project)
    used = config_dir(cfg, skills_dir if arm != "plain" else None)
    prompt = task["plain_prompt"] if arm == "plain" else task["prompt"]
    env = {k_: v for k_, v in os.environ.items() if k_ not in SECRET_ENV}
    env["CLAUDE_CONFIG_DIR"] = str(cfg)
    cmd = [os.environ.get("CLAUDE_BIN", "claude"), "-p", prompt, "--model", model,
           "--max-turns", str(task["max_turns"]), "--output-format", "stream-json", "--verbose",
           "--no-session-persistence", "--strict-mcp-config",
           "--allowedTools", *ALLOWED, "--disallowedTools", *DISALLOWED]
    timed_out = False
    try:
        r = subprocess.run(cmd, cwd=project, env=env, text=True, capture_output=True,
                           timeout=task["timeout_seconds"], stdin=subprocess.DEVNULL)
        stdout, code = r.stdout, r.returncode
    except subprocess.TimeoutExpired as e:
        stdout, code, timed_out = (e.stdout or b"").decode() if isinstance(e.stdout, bytes) else (e.stdout or ""), None, True
    (out / "transcript.jsonl").write_text(stdout)
    events = []
    for line in stdout.splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(event, dict):
            events.append(event)
    result = next((e for e in reversed(events) if e.get("type") == "result"), {})
    (out / "transcript.md").write_text(trim(events))
    (out / "reply.md").write_text(result.get("result", ""))
    diff = changes(project, start)
    (out / "changes.diff").write_text(diff)
    (out / "checks.json").write_text(json.dumps(run_checks(repo, task, project), indent=2))
    meta = {"arm": arm, "run": k, "model": model, "skills": used, "exit": code, "timed_out": timed_out,
            "ended": result.get("subtype"), "turns": result.get("num_turns"),
            "cost_usd": result.get("total_cost_usd"), "duration_ms": result.get("duration_ms"),
            "leaks": leaks(events, task), "changed": bool(diff.strip())}
    (out / "meta.json").write_text(json.dumps(meta, indent=2))
    shutil.rmtree(project.parent, ignore_errors=True)
    shutil.rmtree(cfg, ignore_errors=True)
    return out


def blind_pairs(label_dir, reference_diff):
    keys = label_dir / ".keys"
    keys.mkdir(exist_ok=True)
    for run in sorted(label_dir.glob("*/run-*")):
        if not (run / "changes.diff").exists():
            continue
        pr_is = random.choice("AB")
        for side in "AB":
            d = run / "compare" / side
            d.mkdir(parents=True, exist_ok=True)
            src = reference_diff if side == pr_is else (run / "changes.diff").read_text()
            (d / "changes.diff").write_text(src)
        (keys / f"{run.parent.name}-{run.name}.json").write_text(json.dumps({"original_pr": pr_is}))


def cmd_run(a):
    task, repo = load_task(a.task, a.repo)
    base = Path(a.base).resolve()
    label = f"{datetime.date.today().isoformat()}-{slug(a.model)}"
    label_dir = base / task["id"] / label
    if label_dir.exists():
        sys.exit(f"{label_dir} exists: move it aside or pick another base dir")
    label_dir.mkdir(parents=True)
    arms = [x.strip() for x in a.arms.split(",") if x.strip()]
    unknown = [x for x in arms if x not in ("plain", "skills")]
    if unknown:
        shutil.rmtree(label_dir)
        sys.exit(f"unknown arm(s): {', '.join(unknown)}. The arms are plain and skills.")
    skills_dir = Path(a.skills_dir).expanduser().resolve() if a.skills_dir else Path.home() / ".claude" / "skills"
    loaded = {}
    if "skills" in arms and a.runs > 0:
        names = skill_names(skills_dir) if skills_dir.is_dir() else []
        if not names:
            shutil.rmtree(label_dir)
            sys.exit(f"{skills_dir} holds no skills, so the skills arm would be the plain arm. "
                     "Install skills there, or point --skills-dir at them.")
        with tempfile.TemporaryDirectory() as tmp:
            config_dir(Path(tmp) / "c", skills_dir)
            loaded = {"dir": str(skills_dir), "names": names, "digest": digest(Path(tmp) / "c" / "skills")}
    version = sh([os.environ.get("CLAUDE_BIN", "claude"), "--version"], check=False).stdout.strip()
    (label_dir / "run.json").write_text(json.dumps(
        {"task": task["id"], "pr": task.get("pr"), "model": a.model, "runs": a.runs,
         "arms": arms, "claude_version": version, "skills": loaded,
         "merged_at": str(task.get("merged_at", ""))}, indent=2))

    tmp = base / "p" / secrets.token_hex(6) / "project"
    start = snapshot(repo, task, tmp)
    (label_dir / "base-check.json").write_text(json.dumps(run_checks(repo, task, tmp), indent=2))
    pr_diff = subprocess.run(["git", "-C", str(repo), "diff", "--binary", task["base"], task["head"]],
                             check=True, capture_output=True).stdout
    applied = subprocess.run(["git", "-C", str(tmp), "apply", "--whitespace=nowarn", "-"], input=pr_diff,
                             capture_output=True)
    ref = label_dir / "reference"
    ref.mkdir()
    if applied.returncode:
        (ref / "checks.json").write_text(json.dumps({"error": applied.stderr.decode()[-2000:]}))
    else:
        (ref / "checks.json").write_text(json.dumps(run_checks(repo, task, tmp), indent=2))
    reference_diff = changes(tmp, start)
    (ref / "changes.diff").write_text(reference_diff)
    shutil.rmtree(tmp.parent, ignore_errors=True)

    jobs = [(arm, k) for k in range(1, a.runs + 1) for arm in arms]
    with concurrent.futures.ThreadPoolExecutor(max_workers=a.jobs) as pool:
        futures = {pool.submit(one_run, repo, task, label_dir, base, name, k, a.model,
                               skills_dir): (name, k) for name, k in jobs}
        for f in concurrent.futures.as_completed(futures):
            name, k = futures[f]
            try:
                print(f"done {name} run-{k}: {f.result()}", flush=True)
            except Exception as e:
                print(f"FAILED {name} run-{k}: {e}", flush=True)
                meta = label_dir / name / f"run-{k}" / "meta.json"
                meta.parent.mkdir(parents=True, exist_ok=True)
                meta.write_text(json.dumps({"arm": name, "run": k, "error": str(e)}, indent=2))
    blind_pairs(label_dir, reference_diff)
    print(label_dir)


def rate(values):
    values = [v for v in values if v is not None]
    return f"{sum(values)}/{len(values)}" if values else "–"


def mean(values, fmt):
    values = [v for v in values if isinstance(v, (int, float))]
    return fmt.format(sum(values) / len(values)) if values else "–"


def read(path):
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return None


def checks_ok(c):
    return None if not c or "error" in c else all(x["passed"] for x in c["checks"])


def rubric(g):
    if not g:
        return None
    e = g.get("expectations") or []
    return f"{sum(1 for x in e if x.get('passed'))}/{len(e)}" if e else None


def cmd_summarize(a):
    for d in a.dirs:
        d = Path(d)
        info = read(d / "run.json") or {}
        base_check = read(d / "base-check.json") or {}
        ref = read(d / "reference" / "checks.json") or {}
        print(f"## {info.get('task')} — {info.get('model')}\n")
        print(f"PR #{info.get('pr')}, merged {info.get('merged_at') or '?'}. {info.get('claude_version')}. "
              f"{info.get('runs')} run(s) per arm.\n")
        loaded = info.get("skills") or {}
        if loaded:
            print(f"`skills` loaded {len(loaded['names'])} skill(s) from {loaded['dir']}, digest {loaded['digest']}: "
                  f"{', '.join(loaded['names'])}.\n")
        warnings = []
        if (base_check.get("hidden_tests") or {}).get("passed"):
            warnings.append("The hidden tests already pass on the base commit, so they can't tell a fix from no change.")
        if "error" in ref:
            warnings.append(f"The original PR didn't apply to the base: {ref['error'][:200]}")
        elif ref and not ref["hidden_tests"]["passed"]:
            warnings.append("The original PR fails its own hidden tests here: check setup and test_command.")
        print("| Arm | Hidden tests | Checks | Rubric | vs original PR (W/T/L) | Cost $ | Turns | Min | Leaks |")
        print("| --- | --- | --- | --- | --- | --- | --- | --- | --- |")
        if ref and "error" not in ref:
            g = read(d / "reference" / "grading.json")
            print(f"| original PR | {int(ref['hidden_tests']['passed'])}/1 | {rate([checks_ok(ref)])} | "
                  f"{rubric(g) or '–'} | – | – | – | – | – |")
        arms = info.get("arms") or sorted(p.name for p in d.iterdir() if p.is_dir() and p.name not in ("reference", ".keys"))
        for arm in arms:
            runs = sorted((d / arm).glob("run-*"))
            if not runs:
                continue
            metas = [read(r / "meta.json") or {} for r in runs]
            checks = [read(r / "checks.json") for r in runs]
            wins = {"run": 0, "tie": 0, "pr": 0}
            for r in runs:
                comp, key = read(r / "compare" / "comparison.json"), read(d / ".keys" / f"{arm}-{r.name}.json")
                if comp and key:
                    w = comp.get("winner")
                    wins["tie" if w == "TIE" else "pr" if w == key["original_pr"] else "run"] += 1
            rubrics = [rubric(read(r / "grading.json")) for r in runs]
            rub = [tuple(map(int, x.split("/"))) for x in rubrics if x]
            rub_s = f"{sum(p for p, _ in rub)}/{sum(t for _, t in rub)}" if rub else "–"
            leaked = sum(1 for m in metas if m.get("leaks"))
            print(f"| {arm} | {rate([(c or {}).get('hidden_tests', {}).get('passed') for c in checks])} | "
                  f"{rate([checks_ok(c) for c in checks])} | {rub_s} | "
                  f"{wins['run']}/{wins['tie']}/{wins['pr']} | {mean([m.get('cost_usd') for m in metas], '{:.2f}')} | "
                  f"{mean([m.get('turns') for m in metas], '{:.0f}')} | "
                  f"{mean([(m.get('duration_ms') or 0) / 60000 or None for m in metas], '{:.1f}')} | {leaked} |")
            for r, m in zip(runs, metas):
                if m.get("leaks"):
                    warnings.append(f"{arm}/{r.name} may have seen the PR: {', '.join(m['leaks'])}")
                if m.get("error"):
                    warnings.append(f"{arm}/{r.name} failed to run: {m['error']}")
                elif m.get("timed_out") or (m.get("ended") and m["ended"] != "success"):
                    warnings.append(f"{arm}/{r.name} didn't finish: {'timed out' if m.get('timed_out') else m['ended']}")
                if m and not m.get("error") and not m.get("changed"):
                    warnings.append(f"{arm}/{r.name} changed nothing")
        print()
        for w in warnings:
            print(f"- {w}")
        if warnings:
            print()


def cmd_doctor(a):
    ok = True
    for tool in ("git", "tar", os.environ.get("CLAUDE_BIN", "claude")):
        if not shutil.which(tool):
            print(f"missing: {tool}")
            ok = False
    if ok and a.live:
        with tempfile.TemporaryDirectory() as tmp:
            env = {k: v for k, v in os.environ.items() if k not in SECRET_ENV}
            env["CLAUDE_CONFIG_DIR"] = tmp
            r = subprocess.run([os.environ.get("CLAUDE_BIN", "claude"), "-p", "Reply with the word ok.", "--model", "haiku",
                                "--max-turns", "1", "--no-session-persistence"],
                               cwd=tmp, env=env, text=True, capture_output=True, timeout=180, stdin=subprocess.DEVNULL)
            if r.returncode:
                print("claude can't sign in with an empty CLAUDE_CONFIG_DIR. Set ANTHROPIC_API_KEY, or "
                      "CLAUDE_CODE_OAUTH_TOKEN from `claude setup-token`, and try again.\n" + (r.stdout + r.stderr)[-500:])
                ok = False
    print("ok" if ok else "not ready")
    sys.exit(0 if ok else 1)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    d = sub.add_parser("doctor")
    d.add_argument("--live", action="store_true")
    r = sub.add_parser("run")
    r.add_argument("task")
    r.add_argument("base")
    r.add_argument("--model", required=True)
    r.add_argument("--runs", type=int, default=3)
    r.add_argument("--arms", default="plain,skills")
    r.add_argument("--skills-dir")
    r.add_argument("-j", "--jobs", type=int, default=2)
    r.add_argument("--repo")
    s = sub.add_parser("summarize")
    s.add_argument("dirs", nargs="+")
    a = p.parse_args()
    {"doctor": cmd_doctor, "run": cmd_run, "summarize": cmd_summarize}[a.cmd](a)


if __name__ == "__main__":
    main()
