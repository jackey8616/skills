"""Collect one finished run into the workspace prepare.py made.

    python3 collect.py <iteration-dir> <case> <config> --tokens N --ms N [--transcript <jsonl>]

Takes --tokens and --ms from the run's completion notice, and the transcript
path the subagent tool gave when the run started. Writes, in
<iteration-dir>/<case>/<config>/:

  outputs/reply.md        the run's final reply, from the reply path it was given
  outputs/repo-state.md   git's view of the project after the run, against the
                          HEAD it started from; only if the project is a repo
  transcript.md           every tool call in order, results trimmed
  timing.json

repo-state.md is the evidence for anything about changes to the project: it
comes from git, not from what the run says it did. Prints a one-line summary.
"""
import json
import subprocess
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
        (out / "repo-state.md").write_text(text)
        summary.append("HEAD " + ("unchanged" if unchanged else "CHANGED"))

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
