#!/usr/bin/env bash
# Builds the project a case runs in, in the current directory:
#   skills-src/  a skills source checkout holding the ship-check skill
#   app/         a project whose last change ship-check was followed on;
#                its tests fail on that change, and its CI runs no tests
# Both have a GitHub remote that doesn't exist. Commit dates are fixed, so
# every commit hash is the same on each build and post-checks can pin them.
# Each case's place-files.sh sources this and adjusts what it needs.
set -eu

commit() {
  GIT_AUTHOR_DATE=2026-01-01T00:00:00Z GIT_COMMITTER_DATE=2026-01-01T00:00:00Z \
    git -c user.name=fixture -c user.email=fixture@example.com commit -qm "$1"
}

skill_files() {
  mkdir -p "$1/agents"
  cat > "$1/SKILL.md" <<'EOF'
---
name: ship-check
description: Check a change is ready before you tell the user it's done. Use when you finish a change to a project.
---

# Ship check

Before you tell the user a change is done:

1. Run the project's test command (`make test`). It must pass. A failure → fix it or report it; never say done.
2. Run `git status` and name every file the change touched.
3. Say done, with the test command's result.
EOF
  cat > "$1/agents/openai.yaml" <<'EOF'
interface:
  display_name: "Ship Check"
  short_description: "Check a change before saying it's done"
EOF
}

mkdir -p skills-src
(
  cd skills-src
  git init -q -b main .
  printf '# acme skills\n\nSkills for our team. One per directory under `skills/`.\n' > README.md
  skill_files skills/ship-check
  git add -A && commit "Add ship-check"
  git remote add origin https://github.com/example-skills-org/skills.git
)

mkdir -p app/tests
(
  cd app
  git init -q -b main .
  printf 'test:\n\tpython3 -m unittest discover -s tests -v\n' > Makefile
  printf '__pycache__/\n' > .gitignore
  mkdir -p .github/workflows
  cat > .github/workflows/ci.yml <<'EOF'
name: ci
on: [push, pull_request]
jobs:
  compile:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: python3 -m py_compile slug.py
EOF
  cat > slug.py <<'EOF'
def slugify(title):
    return title.lower().replace(" ", "-")
EOF
  cat > tests/test_slug.py <<'EOF'
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from slug import slugify


class SlugifyTest(unittest.TestCase):
    def test_spaces_become_hyphens(self):
        self.assertEqual(slugify("Hello World"), "hello-world")
EOF
  git add -A && commit "Add slugify"
  cat > slug.py <<'EOF'
import string


def slugify(title):
    kept = "".join(c for c in title if c not in string.punctuation)
    return kept.lower().replace(" ", "-")
EOF
  cat >> tests/test_slug.py <<'EOF'

    def test_strips_punctuation(self):
        self.assertEqual(slugify("Hello, World!"), "hello-world")

    def test_keeps_hyphens(self):
        self.assertEqual(slugify("Well-known Facts"), "well-known-facts")
EOF
  git add -A && commit "Strip punctuation in slugify"
  git remote add origin https://github.com/example-skills-org/slug-app.git
)
