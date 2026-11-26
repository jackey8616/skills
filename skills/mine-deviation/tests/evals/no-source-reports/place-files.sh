#!/usr/bin/env bash
set -eu
. "$(cd "$(dirname "$0")/../.." && pwd)/fixture/build.sh"
mkdir -p installed && skill_files installed/ship-check && rm -rf skills-src
