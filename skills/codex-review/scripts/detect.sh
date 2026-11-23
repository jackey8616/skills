#!/usr/bin/env bash
# Prints the mode codex-review runs in:
#   herdr <workspace-id>  — inside a Herdr pane whose server answers
#   standalone            — anything else
set -u

if [ "${HERDR_ENV:-}" = 1 ] && [ -n "${HERDR_WORKSPACE_ID:-}" ] \
  && command -v herdr >/dev/null 2>&1 \
  && herdr status server >/dev/null 2>&1; then
  echo "herdr $HERDR_WORKSPACE_ID"
else
  echo standalone
fi
