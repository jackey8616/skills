#!/usr/bin/env bash
# Prints the mode codex-review runs in:
#   herdr <workspace-id> <reviewer>  — inside a Herdr pane whose server answers
#   standalone                       — anything else
# <reviewer> is the reviewer agent's name: reviewer-<workspace-id>, in
# lowercase, since Herdr rejects uppercase in agent names.
set -u

if [ "${HERDR_ENV:-}" = 1 ] && [ -n "${HERDR_WORKSPACE_ID:-}" ] \
  && command -v herdr >/dev/null 2>&1 \
  && herdr status server >/dev/null 2>&1; then
  echo "herdr $HERDR_WORKSPACE_ID reviewer-$(printf '%s' "$HERDR_WORKSPACE_ID" | tr '[:upper:]' '[:lower:]')"
else
  echo standalone
fi
