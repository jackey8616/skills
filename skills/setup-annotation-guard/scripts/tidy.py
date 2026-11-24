#!/usr/bin/env python3
"""Tidy what `ast-grep scan -U` leaves behind after deleting comments.

    python3 tidy.py [--base REV] [PATH ...]

Compares each file with its version at REV (default HEAD) and touches only
lines the comment removal changed:

- strips trailing whitespace the removal left;
- drops lines it left blank or whitespace-only (a full-line comment, the
  lines of a multi-line doc comment);
- caps a blank run that a dropped line joined at the longer of the runs it
  joined, so two blank lines between Python definitions stay two;
- removes blank lines it left at the top of the file.

Every other line is kept byte for byte, line ending included. With no PATH,
it tidies every file `git diff --name-only REV` lists.
"""
import argparse
import difflib
import subprocess
import sys

DROP = object()


def git(*args):
    return subprocess.run(["git", *args], check=True, capture_output=True).stdout


def ending(line):
    if line.endswith("\r\n"):
        return "\r\n"
    return "\n" if line.endswith("\n") else ""


def blank(line):
    return line is DROP or not line.strip()


def cuts(old_text, new_text):
    """Offsets in new_text where text from old_text was removed."""
    points = set()
    matcher = difflib.SequenceMatcher(a=old_text, b=new_text, autojunk=False)
    for tag, _, _, j1, j2 in matcher.get_opcodes():
        if tag != "equal":
            points.update(range(j1, j2 + 1))
    return points


def tidy_block(old_block, new_block):
    out = []
    points = cuts("".join(old_block), "".join(new_block))
    start = 0
    for line in new_block:
        end = start + len(line) - len(ending(line))
        here = sorted(p for p in points if start <= p <= end)
        if not here:
            out.append(line)
        elif not line.strip():
            out.append(DROP)
        else:
            body = line[: end - start]
            tail = here[-1] - start
            if not body[tail:].strip():
                body = body[:tail].rstrip() + body[tail:].strip()
            out.append(body + ending(line))
        start += len(line)
    return out


def tidy(old_lines, new_lines):
    out = []
    matcher = difflib.SequenceMatcher(a=old_lines, b=new_lines, autojunk=False)
    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag == "replace":
            out.extend(tidy_block(old_lines[i1:i2], new_lines[j1:j2]))
        else:
            out.extend(new_lines[j1:j2])
    return collapse(out, old_lines)


def collapse(lines, old_lines):
    result = []
    i = 0
    while i < len(lines):
        if not blank(lines[i]):
            result.append(lines[i])
            i += 1
            continue
        start = i
        while i < len(lines) and blank(lines[i]):
            i += 1
        run = lines[start:i]
        if DROP not in run:
            result.extend(run)
            continue
        if not result and old_lines and old_lines[0].strip():
            continue
        parts, current = [], []
        for line in run:
            if line is DROP:
                parts.append(current)
                current = []
            else:
                current.append(line)
        parts.append(current)
        result.extend(max(parts, key=len))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--base", default="HEAD")
    parser.add_argument("paths", nargs="*")
    args = parser.parse_args()

    if args.paths:
        paths = args.paths
    else:
        listed = git("diff", "--name-only", "-z", args.base).decode("utf-8")
        paths = [p for p in listed.split("\0") if p]
    changed = 0
    for path in paths:
        try:
            old = git("show", f"{args.base}:{path}").decode("utf-8").splitlines(keepends=True)
            with open(path, encoding="utf-8", newline="") as f:
                new = f.read().splitlines(keepends=True)
        except (subprocess.CalledProcessError, UnicodeDecodeError, FileNotFoundError):
            print(f"skipped  {path}", file=sys.stderr)
            continue
        tidied = tidy(old, new)
        if tidied != new:
            with open(path, "w", encoding="utf-8", newline="") as f:
                f.writelines(tidied)
            changed += 1
            print(f"tidied   {path}")
    print(f"{changed} file(s) tidied")


if __name__ == "__main__":
    main()
