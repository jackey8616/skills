#!/usr/bin/env bash
# Run the repo's checks and record how each ended.
#
#   bash checks.sh CHECKS OUT
#
# CHECKS has one line per check, `<name>: <command>`, in the order to run
# them; a command of `absent` means the repo has no such check. Run from the
# repo root. Each command runs with bash, whatever shell called this, and
# its output goes to OUT/<name>.log. Prints `<name>  exit <n>` or
# `<name>  absent` per line, and saves the same lines to OUT/status.txt.
# Exits 0 when every check ran, failing or not: a failing check is a result
# to record, not an error. 2 if a record can't be written.
set -u

out="$2"
mkdir -p "$out" && : > "$out/status.txt" || exit 2
while IFS= read -r line || [ -n "$line" ]; do
  [ -n "${line//[[:space:]]/}" ] || continue
  name="${line%%:*}"
  cmd="${line#*:}"
  cmd="${cmd#"${cmd%%[![:space:]]*}"}"
  if [ "$cmd" = absent ]; then
    printf '%s  absent\n' "$name" | tee -a "$out/status.txt" || exit 2
    continue
  fi
  : > "$out/$name.log" || exit 2
  rc=0
  bash -c "$cmd" > "$out/$name.log" 2>&1 < /dev/null || rc=$?
  printf '%s  exit %s\n' "$name" "$rc" | tee -a "$out/status.txt" || exit 2
done < "$1"
