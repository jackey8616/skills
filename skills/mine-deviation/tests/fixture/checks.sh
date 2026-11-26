#!/usr/bin/env bash
# Shared by each case's post-check.sh, run in a copy of the project after a
# run. A repo is unchanged when HEAD is the commit the fixture built, main is
# its only branch, and git sees no file but the caches the tests write.
failed=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; failed=1; fi; }

untouched() {
  [ "$(git -C "$1" rev-parse HEAD)" = "$2" ] \
    && [ "$(git -C "$1" for-each-ref --format='%(refname)' refs/heads)" = refs/heads/main ] \
    && [ -z "$(git -C "$1" status --porcelain --ignored | grep -v '__pycache__/$')" ]
}
