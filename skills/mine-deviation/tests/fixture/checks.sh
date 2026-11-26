#!/usr/bin/env bash
# Shared by each case's post-check.sh, run in a copy of the project after a
# run. A repo is unchanged when HEAD holds the tree the fixture built, its
# history is the fixture's commits by subject, main is its only branch, and
# git sees no file but the caches the tests write. Trees and subjects depend
# only on content, so the pins hold whatever git version builds the fixture.
failed=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; failed=1; fi; }

untouched() {
  [ "$(git -C "$1" rev-parse 'HEAD^{tree}')" = "$2" ] \
    && [ "$(git -C "$1" log --format=%s | tr '\n' '|')" = "$3" ] \
    && [ "$(git -C "$1" for-each-ref --format='%(refname)' refs/heads)" = refs/heads/main ] \
    && [ -z "$(git -C "$1" status --porcelain --ignored | grep -v '__pycache__/$')" ] \
    || { echo "  $1: tree $(git -C "$1" rev-parse 'HEAD^{tree}' 2>&1), log $(git -C "$1" log --format=%s 2>&1 | tr '\n' '|'), heads $(git -C "$1" for-each-ref --format='%(refname)' refs/heads | tr '\n' ' '), status $(git -C "$1" status --porcelain --ignored | tr '\n' ' ')" >&2; return 1; }
}
