#!/usr/bin/env bash
set -u
. "$(cd "$(dirname "$0")/../.." && pwd)/fixture/checks.sh"
check "skills-src/ is unchanged" "untouched skills-src 9dfadca8467706a4be6beae3c474ece8b5e4a531"
check "app/ is unchanged" "untouched app 49ade624b5b04a870e20711106e594d50c89f843"
exit $failed
