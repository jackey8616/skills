#!/usr/bin/env bash
set -eu
files="$(cd "$(dirname "$0")" && pwd)/files"
commit() { git -c user.name=fixture -c user.email=fixture@example.com commit -qm "$1"; }
git init -q -b main .
cp -R "$files/base/." .
git add -A && commit "Parse durations"
git checkout -q -b fix-minutes
cp -R "$files/head/." .
git add -A && commit "Fix minutes in parse_duration, with tests from acme-testkit"
