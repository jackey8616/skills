#!/usr/bin/env python3
"""Tidy what `ast-grep scan -U` leaves behind after deleting comments.

    python3 tidy.py --base REV PASS.jsonl [PASS.jsonl ...]

Each PASS.jsonl is the `--json=stream` output of a scan, taken just before
the same scan ran with -U; give them in the order they ran. Their
replacementOffsets say exactly where text was removed, so nothing is
guessed. For each file they name, compared with its version at REV, it
works on lines only, in every language alike:

- strips trailing whitespace a removal left at the end of a line;
- drops lines a removal left blank or whitespace-only (a full-line comment,
  the lines of a multi-line doc comment), but keeps one empty after a line
  ending in a backslash, which would otherwise continue onto the next;
- caps a blank run that a dropped line joined at the longer of the runs it
  joined, so two blank lines between Python definitions stay two;
- removes blank lines a removal left at the top of the file.

Every other line is kept byte for byte, line ending included. A file whose
current text isn't exactly REV's with the recorded ranges removed is
skipped and reported. Two kinds of line are named for fixing by hand, and
the exit status is 3: one where a removal joined the code on either side
(`return/**/1`, but not next to a bracket, comma, or semicolon), since
what whitespace the comment stood for depends on the language, and one a removal left ending in a backslash, which now
continues onto the next line. Empty JSX `{}` joins nothing, so its
removal is never named.
"""
import argparse
import json
import subprocess
import sys
from collections import defaultdict

DROP = object()


class Named(str):
    """A tidied line to fix by hand, and why."""

    reason = ""


def git(*args):
    return subprocess.run(["git", *args], check=True, capture_output=True).stdout


def ending(line):
    if line.endswith("\r\n"):
        return "\r\n"
    return "\n" if line.endswith("\n") else ""


def lines_of(text):
    """Split after each LF only: CR, U+2028, and U+2029 can be string data."""
    parts = text.split("\n")
    return [p + "\n" for p in parts[:-1]] + ([parts[-1]] if parts[-1] else [])


def blank(line):
    return line is DROP or not line.strip()


def fuses(a, b):
    """Whether two characters a removal brought together may read as one
    token. Brackets, commas, and semicolons are tokens of their own in every
    language ast-grep parses."""
    return not (a.isspace() or b.isspace() or a in "([{,;" or b in ")]},;")


def load(paths):
    passes = []
    for path in paths:
        ranges = defaultdict(list)
        with open(path, encoding="utf-8") as f:
            for line in f:
                if not line.strip():
                    continue
                match = json.loads(line)
                offsets = match.get("replacementOffsets")
                if offsets is None or match.get("replacement") != "":
                    continue
                joins = match["ruleId"] != "empty-jsx"
                ranges[match["file"]].append((offsets["start"], offsets["end"], joins))
        passes.append(ranges)
    return passes


def apply(old, passes):
    """REV's bytes with each pass's ranges removed, and where each cut landed,
    with whether a cut there can join code."""
    text, points = old, []
    for ranges in passes:
        ranges = sorted(ranges)
        out, moved, pos, removed = [], [], 0, 0
        for start, end, joins in ranges:
            if start < pos:
                return None, None
            out.append(text[pos:start])
            moved.append((start - removed, joins))
            removed += end - start
            pos = end
        out.append(text[pos:])
        for point, joins in points:
            shift, landed = 0, None
            for start, end, outer in ranges:
                if point <= start:
                    break
                if point < end:
                    landed = (start - shift, outer)
                    break
                shift += end - start
            moved.append(landed or (point - shift, joins))
        text, points = b"".join(out), moved
    return text, points


def tidy(new, points):
    lines = lines_of(new)
    at = defaultdict(bool)
    for point, joins in points:
        at[point] |= joins
    out, start = [], 0
    for line in lines:
        end = start + len(line) - len(ending(line))
        here = sorted(p for p in at if start <= p <= end)
        if not here:
            out.append(line)
        elif not line.strip():
            kept = [o for o in out if o is not DROP]
            if kept and kept[-1].rstrip("\r\n").endswith("\\"):
                out.append(ending(line) or "\n")
            else:
                out.append(DROP)
        else:
            body = line[: end - start]
            tail = here[-1] - start
            reason = None
            if not body[tail:].strip():
                body = body[:tail].rstrip()
                if body.endswith("\\"):
                    reason = "a removal left it ending in a backslash"
            for p in here:
                i = p - start
                if at[p] and 0 < i < len(body) and fuses(body[i - 1], body[i]):
                    reason = "a removal joined the code on either side"
            if reason:
                out.append(Named(body + ending(line)))
                out[-1].reason = reason
            else:
                out.append(body + ending(line))
        start += len(line)
    return out


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
    parser.add_argument("--base", required=True)
    parser.add_argument("cuts", nargs="+")
    args = parser.parse_args()

    passes = load(args.cuts)
    files = sorted({path for ranges in passes for path in ranges})
    changed, status = 0, 0
    for path in files:
        try:
            old = git("show", f"{args.base}:{path}")
            with open(path, "rb") as f:
                current = f.read()
            expected, byte_points = apply(old, [ranges.get(path, []) for ranges in passes])
            if expected != current:
                print(f"skipped  {path} (not {args.base} minus the recorded removals)", file=sys.stderr)
                continue
            new = current.decode("utf-8")
            points = [(len(current[:p].decode("utf-8")), joins) for p, joins in byte_points]
        except (subprocess.CalledProcessError, UnicodeDecodeError, FileNotFoundError):
            print(f"skipped  {path}", file=sys.stderr)
            continue
        old_lines = lines_of(old.decode("utf-8", errors="replace"))
        tidied = collapse(tidy(new, points), old_lines)
        for n, line in enumerate(tidied, 1):
            if isinstance(line, Named):
                print(f"check    {path}:{n} ({line.reason})", file=sys.stderr)
                status = 3
        if "".join(tidied) != new:
            with open(path, "w", encoding="utf-8", newline="") as f:
                f.writelines(tidied)
            changed += 1
            print(f"tidied   {path}")
    print(f"{changed} file(s) tidied")
    sys.exit(status)


if __name__ == "__main__":
    main()
