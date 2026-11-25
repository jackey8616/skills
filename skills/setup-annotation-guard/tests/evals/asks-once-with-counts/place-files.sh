#!/usr/bin/env bash
set -eu
files="$(cd "$(dirname "$0")" && pwd)/files"
git init -q -b main .
cp -R "$files/base/." .
git add -A
git -c user.name=fixture -c user.email=fixture@example.com commit -qm "Notes store, export script, and sidebar formatting"

