#!/usr/bin/env bash
set -u
. "$(cd "$(dirname "$0")/../.." && pwd)/fixture/checks.sh"
check "skills-src/ is unchanged" "untouched skills-src 4854162e72e371476c8beacda31b9b328713fada"
check "app/ is unchanged" "untouched app 38e8627b162f3572d7662b2772b192347547fcb1"
exit $failed
