"""Collect one finished run into the workspace prepare.py made.

    python3 collect.py <iteration-dir> <case> <config> --tokens N --ms N [--transcript <jsonl>]

Takes --tokens and --ms from the run's completion notice, and the transcript
path the subagent tool gave when the run started. Writes, in
<iteration-dir>/<case>/<config>/:

  outputs/reply.md        the run's final reply, from the reply path it was given
  outputs/repo-state.md   git's view of the project after the run, against the
                          HEAD it started from, if the project is a repo;
  outputs/project-state.md otherwise: the files created and deleted in it
  outputs/changes.diff    for a repo, everything the run changed in it: the
                          diff against HEAD, then each untracked file in full
  outputs/post-check.md   if the case has a post-check.sh: its output and exit
                          status, run in a copy of the project so the run's
                          result is left as it was
  transcript.md           every tool call in order, results trimmed
  timing.json

repo-state.md and project-state.md are the evidence for anything about
changes to the project: they come from the disk, not from what the run says.
Both end with what the run left in its temp directory: a file there means
the run wrote one, which a skill that should only answer mustn't. Prints a one-line summary.
"""
import json
import shutil
import subprocess
import tempfile
import sys
from pathlib import Path


def option(argv, name, default=None):
    if name in argv:
        return argv[argv.index(name) + 1]
    return default


def git(project, *args):
    r = subprocess.run(["git", "-C", project, *args], capture_output=True, text=True)
    return (r.stdout + r.stderr).strip()


def repo_state(run):
    project, start = run["project"], run["start_head"]
    head = git(project, "rev-parse", "HEAD")
    diff = git(project, "diff", "HEAD", "--stat")
    fence = "```"
    return "\n".join([
        "# Project state after the run",
        "",
        f"- HEAD before: `{start}`",
        f"- HEAD after: `{head}` ({'unchanged' if head == start else 'CHANGED'})",
        f"- Branch after: `{git(project, 'branch', '--show-current')}`",
        f"- Branches: `{', '.join(git(project, 'branch', '--format=%(refname:short)').splitlines())}`",
        f"- Reflog entries: {len(git(project, 'reflog').splitlines())}",
        f"- Stash entries: {len(git(project, 'stash', 'list').splitlines())}",
        f"- Worktrees: {len(git(project, 'worktree', 'list').splitlines())} (1 is the project itself)",
        f"- Tracked files changed against HEAD: {'none' if not diff else chr(10) + fence + chr(10) + diff + chr(10) + fence}",
        "- `git status --porcelain --ignored`:",
        fence,
        git(project, "status", "--porcelain", "--ignored") or "(clean)",
        fence,
        "",
    ]), head == start


def project_state(run):
    project = Path(run["project"])
    now = sorted(str(f.relative_to(project)) for f in project.rglob("*")
                 if f.is_file() and ".git" not in f.relative_to(project).parts)
    before = run.get("start_files") or []
    created = [f for f in now if f not in before]
    deleted = [f for f in before if f not in now]
    lines = ["# Project state after the run", "",
             f"- Files before: {len(before)}; after: {len(now)}",
             "- Created: " + (", ".join(f"`{f}`" for f in created) or "none"),
             "- Deleted: " + (", ".join(f"`{f}`" for f in deleted) or "none"),
             "- Content changes in files that existed before aren't tracked; a project that isn't a git repo has no baseline for them.",
             ""]
    return "\n".join(lines), not created and not deleted


def temp_files(run):
    tmp = Path(run["tmp"])
    left = sorted(str(f.relative_to(tmp)) for f in tmp.rglob("*") if f.is_file()) if tmp.is_dir() else []
    return "- Left in the temp directory: " + (", ".join(f"`{f}`" for f in left) or "nothing") + "\n"


def changes(run):
    project = run["project"]
    diff = subprocess.run(["git", "-C", project, "diff", "HEAD"], capture_output=True, text=True).stdout
    untracked = git(project, "ls-files", "--others", "--exclude-standard").splitlines()
    for f in untracked:
        r = subprocess.run(["git", "-C", project, "diff", "--no-index", "--", "/dev/null", f],
                           capture_output=True, text=True)
        diff += r.stdout
    return diff or "(no changes)\n"


def post_check(run):
    with tempfile.TemporaryDirectory() as d:
        copy = Path(d) / "project"
        shutil.copytree(run["project"], copy, symlinks=True)
        try:
            r = subprocess.run(["bash", run["post_check"]], cwd=copy, capture_output=True, text=True, timeout=900)
            out, code = r.stdout + r.stderr, r.returncode
        except subprocess.TimeoutExpired as e:
            out, code = (e.stdout or "") + "\n(timed out after 900s)", "timeout"
    fence = "```"
    return f"# Post-check, on a copy of the project\n\nExit: {code}\n\n{fence}\n{out.rstrip()}\n{fence}\n", code == 0


def trim(text, n):
    text = text if isinstance(text, str) else json.dumps(text)
    return text if len(text) <= n else text[:n] + f"\n… [{len(text) - n} more chars]"


def transcript(path):
    lines, step = ["# Transcript: tool calls in order", ""], 0
    for raw in Path(path).read_text().splitlines():
        try:
            d = json.loads(raw)
        except json.JSONDecodeError:
            continue
        msg = d.get("message")
        if not isinstance(msg, dict) or not isinstance(msg.get("content"), list):
            continue
        for c in msg["content"]:
            kind = c.get("type")
            if kind == "tool_use":
                step += 1
                inp = c.get("input") or {}
                if c.get("name") == "Bash":
                    body = "```bash\n" + inp.get("command", "") + "\n```"
                else:
                    shown = {k: v for k, v in inp.items() if k not in ("content", "old_string", "new_string")}
                    body = "`" + trim(json.dumps(shown), 600) + "`"
                    if c.get("name") == "Write":
                        body += "\n```\n" + trim(inp.get("content", ""), 600) + "\n```"
                lines += [f"## {step}. {c.get('name')}", body, ""]
            elif kind == "tool_result":
                content = c.get("content")
                if isinstance(content, list):
                    content = "\n".join(x.get("text", "") for x in content if isinstance(x, dict))
                lines += ["Result:", "```", trim(content or "", 1200), "```", ""]
            elif kind == "text" and d.get("type") == "assistant":
                lines += ["Says:", "> " + trim(c.get("text", ""), 800).replace("\n", "\n> "), ""]
    return "\n".join(lines) + "\n", step


def main(argv):
    if len(argv) < 3 or "--tokens" not in argv or "--ms" not in argv:
        sys.exit(__doc__)
    it, case, config = Path(argv[0]), argv[1], argv[2]
    tokens, ms = int(option(argv, "--tokens")), int(option(argv, "--ms"))
    transcript_path = option(argv, "--transcript")
    run_dir = it / case / config
    run = json.loads((run_dir / "run.json").read_text())
    out = run_dir / "outputs"
    out.mkdir(exist_ok=True)

    reply = Path(run["reply"])
    (out / "reply.md").write_text(reply.read_text() if reply.is_file() else "(the run wrote no reply)\n")
    summary = [f"{case}/{config}", "reply " + ("found" if reply.is_file() else "MISSING")]

    if run["start_head"]:
        text, unchanged = repo_state(run)
        (out / "repo-state.md").write_text(text + temp_files(run))
        (out / "changes.diff").write_text(changes(run))
        summary.append("HEAD " + ("unchanged" if unchanged else "CHANGED"))
    else:
        text, unchanged = project_state(run)
        (out / "project-state.md").write_text(text + temp_files(run))
        summary.append("files " + ("unchanged" if unchanged else "CHANGED"))

    if run.get("post_check"):
        text, passed = post_check(run)
        (out / "post-check.md").write_text(text)
        summary.append("post-check " + ("passed" if passed else "FAILED"))

    if transcript_path and Path(transcript_path).is_file():
        text, steps = transcript(transcript_path)
        (run_dir / "transcript.md").write_text(text)
        summary.append(f"{steps} tool calls")
    else:
        summary.append("no transcript")

    (run_dir / "timing.json").write_text(json.dumps(
        {"total_tokens": tokens, "duration_ms": ms, "total_duration_seconds": round(ms / 1000, 1)}, indent=2) + "\n")
    print(": ".join([summary[0], ", ".join(summary[1:])]))


if __name__ == "__main__":
    main(sys.argv[1:])
