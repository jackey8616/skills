import re

UNITS = {"h": 3600, "m": 1, "s": 1}
PART = re.compile(r"(\d+)([hms])")


def parse_duration(text):
    parts = PART.findall(text)
    if not parts or "".join(n + u for n, u in parts) != text:
        raise ValueError(f"not a duration: {text!r}")
    return sum(int(n) * UNITS[u] for n, u in parts)
