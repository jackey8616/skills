#!/usr/bin/env python3
"""Tidy what `ast-grep scan -U` leaves behind after deleting comments.

    python3 tidy.py [--base REV] [PATH ...]

Compares each file with its version at REV (default HEAD) and touches only
lines the comment removal changed:

- strips trailing whitespace the removal left;
- drops lines it left blank or whitespace-only (a full-line comment, the
  lines of a multi-line doc comment);
- drops a `{}` it left behind (JSX `{/* … */}`), when the old text had none;
- caps a blank run that the drop merged at the longer of its original runs,
  so two blank lines between Python definitions stay two;
- removes blank lines it left at the top of the file.

Lines the removal didn't change are never touched. With no PATH, it tidies
every file `git diff --name-only REV` lists.
"""
import argparse
import difflib
import subprocess
import sys

DROP = object()


def git(*args):
    return subprocess.run(["git", *args], check=True, capture_output=True, text=True).stdout


def tidy(old_lines, new_lines):
    out = []
    matcher = difflib.SequenceMatcher(a=old_lines, b=new_lines, autojunk=False)
    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag != "replace":
            out.extend(new_lines[j1:j2])
            continue
        old_text = "".join(old_lines[i1:i2])
        for line in new_lines[j1:j2]:
            body = line.rstrip()
            if "{}" in body and "{}" not in old_text:
                body = body.replace("{}", "").rstrip()
            if body.strip():
                out.append(body + "\n")
            else:
                out.append(DROP)
    return collapse(out, old_lines)


def collapse(lines, old_lines):
    result = []
    i = 0
    while i < len(lines):
        if lines[i] is not DROP and lines[i].strip():
            result.append(lines[i])
            i += 1
            continue
        runs, current, dropped = [], 0, False
        while i < len(lines) and (lines[i] is DROP or not lines[i].strip()):
            if lines[i] is DROP:
                runs.append(current)
                current, dropped = 0, True
            else:
                current += 1
            i += 1
        runs.append(current)
        if not dropped:
            result.extend(["\n"] * current)
        elif result or (old_lines and not old_lines[0].strip()):
            result.extend(["\n"] * max(runs))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--base", default="HEAD")
    parser.add_argument("paths", nargs="*")
    args = parser.parse_args()

    paths = args.paths or git("diff", "--name-only", args.base).split()
    changed = 0
    for path in paths:
        try:
            old = git("show", f"{args.base}:{path}").splitlines(keepends=True)
            with open(path, encoding="utf-8") as f:
                new = f.read().splitlines(keepends=True)
        except (subprocess.CalledProcessError, UnicodeDecodeError, FileNotFoundError):
            print(f"skipped  {path}", file=sys.stderr)
            continue
        if new and not new[-1].endswith("\n"):
            new[-1] += "\n"
        tidied = tidy(old, new)
        if tidied != new:
            with open(path, "w", encoding="utf-8") as f:
                f.writelines(tidied)
            changed += 1
            print(f"tidied   {path}")
    print(f"{changed} file(s) tidied")


if __name__ == "__main__":
    main()
