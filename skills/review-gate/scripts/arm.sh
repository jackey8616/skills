#!/usr/bin/env bash
# Arms or disarms the review gate for this repo.
#   arm.sh --base <rev> --source <label> --requirement-file <file> [--max-rounds N]
#   arm.sh --off
#   arm.sh --status
# State lives in <git-dir>/review-gate/, outside the working tree, so the
# tree fingerprint and the reviewer never see it.
set -euo pipefail

gd="$(git rev-parse --absolute-git-dir)"
st="$gd/review-gate"
here="$(cd "$(dirname "$0")" && pwd)"

case "${1:-}" in
  --off) rm -f "$st/armed"; echo "review-gate: disarmed"; exit 0 ;;
  --status)
    if [ -f "$st/armed" ]; then
      echo "armed: session=$(cat "$st/armed") base=$(cat "$st/base") round=$(cat "$st/round")/$(cat "$st/max")"
    else echo "disarmed"; fi
    [ -f "$st/rounds.tsv" ] && cat "$st/rounds.tsv"
    exit 0 ;;
esac

base= source= req= max=10
while [ $# -gt 0 ]; do
  case "$1" in
    --base) base="$2"; shift 2 ;;
    --source) source="$2"; shift 2 ;;
    --requirement-file) req="$2"; shift 2 ;;
    --max-rounds) max="$2"; shift 2 ;;
    *) echo "arm.sh: unknown argument $1" >&2; exit 2 ;;
  esac
done
[ -n "$base" ] && [ -n "$source" ] && [ -f "$req" ] \
  || { echo "arm.sh: need --base, --source and --requirement-file" >&2; exit 2; }

mkdir -p "$st"
git rev-parse --verify "$base^{commit}" > "$st/base"
printf '%s\n' "$source" > "$st/source"
cp "$req" "$st/requirement.md"
echo "$max" > "$st/max"
echo 0 > "$st/round"
: > "$st/rounds.tsv"
rm -f "$st"/report-*.md "$st"/prompt-*.md
echo "$here/stop-gate.sh" > "$st/gate-path"
# Tie the gate to this session, so another session in the same repo isn't gated.
echo "${CLAUDE_CODE_SESSION_ID:-any}" > "$st/armed"
echo "review-gate: armed (base $(cut -c1-12 "$st/base"), up to $max rounds)"
