#!/usr/bin/env bash
set -eu
. "$(cd "$(dirname "$0")/../.." && pwd)/fixture/build.sh"
cat > skills-src/skills/ship-check/tests/deviations.md <<"EOF"
## 2026-10-02 — said done without running make test
- Step: "Run the project's test command (`make test`). It must pass."
- What happened: told the user a change was done without running make test.
- Cause: ambiguous step
- Fix: wording: step 1 now says a failure means never say done
- Evidence: unverified: the run depended on a long session
- Recurrence of: none
EOF
(cd skills-src && git add -A && git -c user.name=fixture -c user.email=fixture@example.com commit -qm "Record a ship-check deviation")
