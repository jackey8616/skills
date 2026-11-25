#!/usr/bin/env bash
# Tests for skills/codex-review/scripts/detect.sh. Offline: a fake `herdr`
# on PATH stands in for the real one, and each case runs in a scrubbed env.
#
#   bash skills/codex-review/tests/detect.test.sh
set -uo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DETECT="$SKILL_DIR/scripts/detect.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0
ok()   { pass=$((pass + 1)); echo "  ok   $1"; }
bad()  { fail=$((fail + 1)); echo "  FAIL $1 — got: $2"; }

# A fake herdr whose `status server` exits with $FAKE_HERDR_RC.
mkdir -p "$WORK/bin" "$WORK/nobin"
cat > "$WORK/bin/herdr" <<'EOF'
#!/usr/bin/env bash
[ "$1 $2" = "status server" ] || exit 64
exit "${FAKE_HERDR_RC:-0}"
EOF
chmod +x "$WORK/bin/herdr"

# expect <name> <want> <bin-dir> [VAR=value...] — run detect.sh with only
# PATH and the given vars set. Passes only if it exits 0 and prints <want>.
expect() {
  local name="$1" want="$2" bin="$3"; shift 3
  local got rc=0
  got="$(env -i PATH="$bin:/usr/bin:/bin" "$@" bash "$DETECT" 2>&1)" || rc=$?
  if [ "$rc" -eq 0 ] && [ "$got" = "$want" ]; then
    ok "$name"
  else
    bad "$name" "exit $rc, output: $got"
  fi
}

expect "no HERDR_ENV → standalone" \
  standalone "$WORK/bin" HERDR_WORKSPACE_ID=w42
expect "HERDR_ENV not 1 → standalone" \
  standalone "$WORK/bin" HERDR_ENV=0 HERDR_WORKSPACE_ID=w42
expect "no workspace id → standalone" \
  standalone "$WORK/bin" HERDR_ENV=1
expect "herdr not installed → standalone" \
  standalone "$WORK/nobin" HERDR_ENV=1 HERDR_WORKSPACE_ID=w42
expect "server not answering → standalone" \
  standalone "$WORK/bin" HERDR_ENV=1 HERDR_WORKSPACE_ID=w42 FAKE_HERDR_RC=1
expect "inside a live Herdr pane → herdr <workspace> <reviewer>" \
  "herdr w42 reviewer-w42" "$WORK/bin" HERDR_ENV=1 HERDR_WORKSPACE_ID=w42
expect "uppercase workspace id → reviewer name in lowercase, id as is" \
  "herdr w1M reviewer-w1m" "$WORK/bin" HERDR_ENV=1 HERDR_WORKSPACE_ID=w1M

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
