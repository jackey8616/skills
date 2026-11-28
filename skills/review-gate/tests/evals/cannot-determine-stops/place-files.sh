#!/usr/bin/env bash
set -eu
git init -q -b main .
cp -R "$(dirname "$0")/files/." .
git add -A
git -c user.name=fixture -c user.email=fixture@example.com commit -qm "Initial commit"
