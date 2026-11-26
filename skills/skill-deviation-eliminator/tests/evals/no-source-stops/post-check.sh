#!/usr/bin/env bash
set -u
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; failed=1; fi; }
failed=0
check "app/ is still at the punctuation change" "[ \"\$(git -C app log -1 --format=%s)\" = \"Strip punctuation in slugify\" ]"
check "app/ has no uncommitted changes" "[ -z \"\$(git -C app status --porcelain)\" ]"
check "installed/ship-check/SKILL.md is unchanged" "[ \"\$(cksum < installed/ship-check/SKILL.md)\" = '2926768661 419' ]"
check "the project holds no files beyond app/ and installed/ship-check" "[ -z \"\$(find . -path ./app -prune -o -type f -print | grep -v -e '^./installed/ship-check/SKILL.md\$' -e '^./installed/ship-check/agents/openai.yaml\$')\" ]"
exit $failed
