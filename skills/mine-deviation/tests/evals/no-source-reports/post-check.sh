#!/usr/bin/env bash
set -u
. "$(cd "$(dirname "$0")/../.." && pwd)/fixture/checks.sh"
check "app/ is unchanged" "untouched app 38e8627b162f3572d7662b2772b192347547fcb1"
check "installed/ship-check is unchanged" "[ \"\$(cat installed/ship-check/SKILL.md installed/ship-check/agents/openai.yaml | cksum)\" = '850803630 521' ] && [ \"\$(find installed -type f | sort | tr '\\n' ' ')\" = 'installed/ship-check/SKILL.md installed/ship-check/agents/openai.yaml ' ]"
exit $failed
