#!/usr/bin/env bash
set -u
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; failed=1; fi; }
failed=0
check "app/ is still at the punctuation change" "[ \"\$(git -C app log -1 --format=%s)\" = \"Strip punctuation in slugify\" ]"
check "app/ has no uncommitted changes" "[ -z \"\$(git -C app status --porcelain)\" ]"
f=skills-src/skills/ship-check/tests/deviations.md
first="$(git -C skills-src log --format=%H --grep='Record a ship-check deviation' -1)"
check "deviations.md has exactly one entry heading" "[ \"\$(grep -c '^## ' $f)\" = 1 ]"
check "that entry was extended" "[ \"\$(git -C skills-src show $first:skills/ship-check/tests/deviations.md)\" != \"\$(cat $f)\" ]"
exit $failed
