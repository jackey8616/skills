#!/usr/bin/env bash
# Checks the repository a full setup leaves, run by skills-audit's collect.py
# in a copy of it. Prints one line per check; the grader reads them.
set -u
say() { if eval "$2" >/dev/null 2>&1; then echo "ok   $1"; else echo "FAIL $1"; fi; }
say "make test passes" "make -s test"
say "a lint target exists and passes" "make -s lint"
say "ast-grep's rule tests pass" "ast-grep test --skip-snapshot-tests"
say "lint fails on a new comment, and only then" "( make -s lint && printf 'x = 1  # new\n' > probe_comment.py && ! make -s lint; r=\$?; rm -f probe_comment.py; exit \$r )"
say "rules exist for Python, TypeScript, and YAML" "ls rules/ | grep -q python && ls rules/ | grep -qi typescript && ls rules/ | grep -qi yaml"
say "the shebang is kept" "head -1 scripts/export.py | grep -qx '#!/usr/bin/env python3'"
say "the noqa is kept" "grep -q '# noqa: E501' notes/store.py"
say "prose comments are gone from notes/, scripts/, tests/, web/" "! grep -rqE '# (Notes live|indent keeps|Print every|A fresh install)|// The sidebar' notes scripts tests web"
say "eslint-disable is gone" "! grep -rq eslint-disable web"
say "docstrings and the JSDoc are gone" "! grep -q '\"\"\"' notes/store.py && ! grep -q '/\*\*' web/format.ts"
say "vendor/ is untouched" "git diff --quiet HEAD -- vendor"
say "the Makefile and pyproject.toml comments are gone" "! grep -q '^# Run the unit tests' Makefile && ! grep -q '^# Ruff checks' pyproject.toml"
say "the CI workflow comment is gone" "! grep -q 'Production runs' .github/workflows/ci.yml"
say "CI runs lint" "grep -qE 'make lint|ast-grep (scan|test)' .github/workflows/ci.yml"
say "CI installs ast-grep 0.39.5" "grep -q '0.39.5' .github/workflows/ci.yml"
say "agent instructions tell agents to run lint" "grep -qi lint CLAUDE.md && grep -qi lint AGENTS.md"
say "nothing committed" "[ \"\$(git rev-list --count HEAD)\" = 1 ]"
