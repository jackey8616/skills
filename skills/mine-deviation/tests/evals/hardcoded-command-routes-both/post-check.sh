#!/usr/bin/env bash
set -u
. "$(cd "$(dirname "$0")/../.." && pwd)/fixture/checks.sh"
check "skills-src/ is unchanged" "untouched skills-src 576cbcf73a3e4ee2c9f81a13c3c12281afa42f84 'Add ship-check|'"
check "app/ is unchanged" "untouched app 97a3a3fb9625c76d4fe98a02621ad18d4f86556a 'Run tests with make check|Strip punctuation in slugify|Add slugify|'"
exit $failed
