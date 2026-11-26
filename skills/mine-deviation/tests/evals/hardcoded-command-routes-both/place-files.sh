#!/usr/bin/env bash
set -eu
. "$(cd "$(dirname "$0")/../.." && pwd)/fixture/build.sh"
sed -i "s/^test:/check:/" app/Makefile && printf "# slug-app\n\nRun the tests with \`make check\`.\n" > app/README.md && (cd app && git add -A && commit "Run tests with make check")
