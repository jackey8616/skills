#!/usr/bin/env bash
set -u
. "$(cd "$(dirname "$0")/../.." && pwd)/fixture/checks.sh"
check "app/ is unchanged" "untouched app b1562f85dcf04fc2e0c4ab08be655da328f037a5 'Strip punctuation in slugify|Add slugify|'"
check "installed/ship-check is unchanged" "[ \"\$(cat installed/ship-check/SKILL.md installed/ship-check/agents/openai.yaml | cksum)\" = '850803630 521' ] && [ \"\$(find installed -type f | sort | tr '\\n' ' ')\" = 'installed/ship-check/SKILL.md installed/ship-check/agents/openai.yaml ' ]"
exit $failed
