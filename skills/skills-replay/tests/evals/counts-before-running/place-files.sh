#!/usr/bin/env bash
set -eu
commit() { git -c user.name="Dana Wu" -c user.email=dana@example.com commit -qm "$@"; }
git init -q -b main .
cat > duration.py <<'PY'
import re


def parse_duration(text):
    """Seconds in a duration like "1h30m" or "45s"."""
    units = {"h": 3600, "m": 1, "s": 1}
    return sum(int(n) * units[u] for n, u in re.findall(r"(\d+)([hms])", text))
PY
cat > test_hours.py <<'PY'
import unittest

from duration import parse_duration


class Hours(unittest.TestCase):
    def test_hours(self):
        self.assertEqual(parse_duration("2h"), 7200)


if __name__ == "__main__":
    unittest.main()
PY
printf "test:\n\tpython3 -m unittest -q\n" > Makefile
printf "__pycache__/\n" > .gitignore
git add -A && commit "Parse durations"
git checkout -q -b fix-minutes
sed -i "s/\"m\": 1,/\"m\": 60,/" duration.py
cat > test_minutes.py <<'PY'
import unittest

from duration import parse_duration


class Minutes(unittest.TestCase):
    def test_hours_and_minutes(self):
        self.assertEqual(parse_duration("1h30m"), 5400)


if __name__ == "__main__":
    unittest.main()
PY
git add -A && commit "Count minutes as 60 seconds"
git checkout -q main
printf "# duration\n\nparse_duration turns \"1h30m\" into seconds.\n" > README.md
git add -A && commit "Add a README"
git -c user.name="Dana Wu" -c user.email=dana@example.com merge -q --no-ff fix-minutes -m "Merge pull request #12 from dana/fix-minutes" -m "Parse minutes in durations"
git branch -q -D fix-minutes
mkdir -p .skills-replay/app-pr12
cat > .skills-replay/app-pr12/task.yaml <<YAML
id: app-pr12
pr: 12
merged_at: 2026-10-02
base: $(git merge-base HEAD^1 HEAD^2)
head: $(git rev-parse HEAD^2)
prompt: |
  parse_duration("1h30m") returns 3630, it should be 5400. Fix it.
hidden_tests: [test_minutes.py]
test_command: python3 -m unittest -q test_minutes
checks:
  - name: all tests
    run: make test
rubric:
  - parse_duration counts a minute as 60 seconds
  - Hours and seconds parse as before
max_turns: 40
timeout_seconds: 900
YAML
git add -A && commit "Add a replay task for #12"
