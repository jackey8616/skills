#!/usr/bin/env bash
set -eu
. "$(cd "$(dirname "$0")/../.." && pwd)/fixture/build.sh"
mkdir -p skills-src/.github/ISSUE_TEMPLATE && cat > skills-src/.github/ISSUE_TEMPLATE/deviation.md <<"EOT"
---
name: Skill deviation
about: A run did not do what a skill says
labels: deviation
---

## Observed

## Expected by the SOP

## Suspected cause

## How to reproduce
EOT
(cd skills-src && git add -A && commit "Add a deviation issue template")
