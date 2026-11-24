#!/usr/bin/env python3
"""Tidy what `ast-grep scan -U` leaves behind after deleting comments.

    python3 tidy.py --base REV PASS.jsonl [PASS.jsonl ...]

Each PASS.jsonl is the `--json=stream` output of a scan, taken just before
the same scan ran with -U; give them in the order they ran. Their
replacementOffsets say exactly where text was removed, so nothing is
guessed. For each file they name, compared with its version at REV:

- strips trailing whitespace a removal left at the end of a line;
- drops lines a removal left blank or whitespace-only (a full-line comment,
  the lines of a multi-line doc comment), but keeps one empty after a line
  ending in a backslash, which would otherwise continue onto the next;
- caps a blank run that a dropped line joined at the longer of the runs it
  joined, so two blank lines between Python definitions stay two;
- removes blank lines a removal left at the top of the file;
- puts back the whitespace a comment stood for where its removal joined
  code, by the language's own rule (WHITESPACE below). In JavaScript and
  TypeScript a comment holding a line terminator (LF, CR, U+2028, U+2029)
  is a line break, and in Go one holding an LF is
  (`return/*\n*/1` keeps its automatic semicolon); in C it is one space
  even then, or a `#define` would end early; in CSS it separates two
  names and is nothing otherwise (`@media/**/screen` needs its space,
  `a/**/:hover` is `a:hover`). Elsewhere a space goes in only between two
  non-whitespace characters, and not just inside brackets or next to `,`
  and `;`.

Cuts from HTML comments are left as -U made them: in `<pre>` every space
and line is content. Empty JSX `{}` joins nothing.

Every other line is kept byte for byte, line ending included. A file whose
current text isn't exactly REV's with the recorded ranges removed is
skipped and reported. A line a removal left ending in a backslash, which
now continues onto the next line, is named for fixing by hand, and the
exit status is 3.
"""
import argparse
import json
import subprocess
import sys
from collections import defaultdict

DROP = object()
LINE, SPACE, NAMES, NOTHING, UNTOUCHED = "line", "space", "names", "nothing", "untouched"
WHITESPACE = {"css": NAMES, "html": UNTOUCHED}
LINE_BREAKS = {
    "javascript": "\n\r\u2028\u2029", "typescript": "\n\r\u2028\u2029", "tsx": "\n\r\u2028\u2029",
    "go": "\n",
}


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


def needs_space(a, b, stands_for):
    if stands_for == NAMES:
        return all(c.isalnum() or c in "-_" or ord(c) > 127 for c in (a, b))
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
                if match["ruleId"] == "empty-jsx":
                    stands_for = NOTHING
                else:
                    language = match.get("language", "").lower()
                    stands_for = WHITESPACE.get(language, SPACE)
                    if any(c in match["text"] for c in LINE_BREAKS.get(language, "")):
                        stands_for = LINE
                ranges[match["file"]].append((offsets["start"], offsets["end"], stands_for))
        passes.append(ranges)
    return passes


def apply(old, passes):
    """REV's bytes with each pass's ranges removed, and where each cut landed,
    with the whitespace its removed text stood for."""
    text, points = old, []
    for ranges in passes:
        ranges = sorted(ranges)
        out, moved, pos, removed = [], [], 0, 0
        for start, end, stands_for in ranges:
            if start < pos:
                return None, None
            out.append(text[pos:start])
            moved.append((start - removed, stands_for))
            removed += end - start
            pos = end
        out.append(text[pos:])
        for point, stands_for in points:
            shift, landed = 0, None
            for start, end, outer in ranges:
                if point <= start:
                    break
                if point < end:
                    landed = (start - shift, outer)
                    break
                shift += end - start
            moved.append(landed or (point - shift, stands_for))
        text, points = b"".join(out), moved
    return text, points


def tidy(new, points, continued):
    lines = lines_of(new)
    at = defaultdict(set)
    for point, stands_for in points:
        if stands_for != UNTOUCHED:
            at[point].add(stands_for)
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
            joined = False
            if not body[tail:].strip():
                body = body[:tail].rstrip()
                joined = body.endswith("\\")
            indent = body[: len(body) - len(body.lstrip())]
            for p in reversed(here):
                i = p - start
                if i >= len(body) or not body[:i].strip() or at[p] == {NOTHING}:
                    continue
                if LINE in at[p]:
                    body = body[:i].rstrip() + (ending(line) or "\n") + indent + body[i:].lstrip()
                elif any(needs_space(body[i - 1], body[i], w) for w in at[p] - {NOTHING}):
                    body = body[:i] + " " + body[i:]
            out.append(body + ending(line))
            if joined:
                continued.append(out[-1])
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
            points = [(len(current[:p].decode("utf-8")), stands_for) for p, stands_for in byte_points]
        except (subprocess.CalledProcessError, UnicodeDecodeError, FileNotFoundError):
            print(f"skipped  {path}", file=sys.stderr)
            continue
        old_lines = lines_of(old.decode("utf-8", errors="replace"))
        continued = []
        tidied = collapse(tidy(new, points, continued), old_lines)
        for n, line in enumerate(tidied, 1):
            if any(line is c for c in continued):
                print(f"check    {path}:{n} (a removal left it ending in a backslash)", file=sys.stderr)
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
