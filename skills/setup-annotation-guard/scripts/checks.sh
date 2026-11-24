#!/usr/bin/env bash
# Run the repo's checks and record how each ended.
#
#   bash checks.sh CHECKS OUT
#
# CHECKS has one line per check, `<name>: <command>`, in the order to run
# them; a command of `absent` means the repo has no such check. Run from the
# repo root. Each command runs with bash, whatever shell called this, and
# its output goes to OUT/<name>.log. Prints `<name>  exit <n>` or
# `<name>  absent` per line, and exits 0: a failing check is a result to
# record, not an error.
set -u

out="$2"
mkdir -p "$out" || exit 2
while IFS= read -r line || [ -n "$line" ]; do
  [ -n "${line//[[:space:]]/}" ] || continue
  name="${line%%:*}"
  cmd="${line#*:}"
  cmd="${cmd#"${cmd%%[![:space:]]*}"}"
  if [ "$cmd" = absent ]; then
    printf '%s  absent\n' "$name"
    continue
  fi
  rc=0
  bash -c "$cmd" > "$out/$name.log" 2>&1 < /dev/null || rc=$?
  printf '%s  exit %s\n' "$name" "$rc"
done < "$1"
