#!/usr/bin/env bash
# Checks every skill against the rules in CLAUDE.md: frontmatter, the Codex
# yaml, invocation set the same way in both harnesses, the README table, the
# scripts SKILL.md points at, and a listed test for every script.
#
#   bash lint-skills.sh [repo-root]
#
# Prints one FAIL line per broken rule and exits 1 if there is any. WARN lines
# don't change the exit status.
set -uo pipefail

ROOT="${1:-$(cd "$(dirname "$0")" && pwd)}"
MAX_LINES=500
MAX_DESCRIPTION=1024

fails=0
fail() { fails=$((fails + 1)); echo "FAIL $1"; }
warn() { echo "WARN $1"; }

# frontmatter <file> — the lines between the opening and closing `---`.
# Prints nothing if line 1 isn't `---` or the block never closes.
frontmatter() {
  awk 'NR == 1 { if ($0 != "---") exit; open = 1; next }
       $0 == "---" { closed = 1; exit }
       { block = block $0 "\n" }
       END { if (closed) printf "%s", block }' "$1"
}

# field <key> — the value of a top-level `key:` line on stdin, quotes stripped.
field() {
  awk -v key="$1" 'index($0, key ":") == 1 {
      v = substr($0, length(key) + 2); sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
      if (v ~ /^".*"$/ || v ~ /^\047.*\047$/) v = substr(v, 2, length(v) - 2)
      print v; exit }'
}

# yaml_value <key> <file> — the value of the first `key:` line at any depth.
yaml_value() {
  sed -n "s/^[[:space:]]*$1:[[:space:]]*//p" "$2" | head -n1 |
    sed -e 's/[[:space:]]*$//' -e 's/^"\(.*\)"$/\1/'
}

[ -d "$ROOT/skills" ] || { echo "FAIL no skills/ directory in $ROOT"; exit 1; }

for dir in "$ROOT"/skills/*/; do
  dir="${dir%/}"
  name="$(basename "$dir")"
  at="skills/$name"
  skill="$dir/SKILL.md"
  yaml="$dir/agents/openai.yaml"

  if [ ! -f "$skill" ]; then
    fail "$at: no SKILL.md"
    continue
  fi

  fm="$(frontmatter "$skill")"
  if [ -z "$fm" ]; then
    fail "$at/SKILL.md: no frontmatter (line 1 must be ---, closed by another ---)"
    continue
  fi

  fm_name="$(printf '%s' "$fm" | field name)"
  if [ "$fm_name" != "$name" ]; then
    fail "$at/SKILL.md: name is '$fm_name', the directory is '$name'"
  fi
  if ! printf '%s' "$name" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$' || [ "${#name}" -gt 64 ]; then
    fail "$at: name must be lowercase words joined by hyphens, at most 64 characters"
  fi

  description="$(printf '%s' "$fm" | field description)"
  case "$description" in
    "") fail "$at/SKILL.md: no description" ;;
    "|"* | ">"*) fail "$at/SKILL.md: description must be on the description: line itself" ;;
  esac
  if [ "${#description}" -gt "$MAX_DESCRIPTION" ]; then
    fail "$at/SKILL.md: description is ${#description} characters, the limit is $MAX_DESCRIPTION"
  fi

  dmi="$(printf '%s' "$fm" | field disable-model-invocation)"
  case "$dmi" in
    true) user_invoked=1 ;;
    "") user_invoked=0 ;;
    *)
      fail "$at/SKILL.md: disable-model-invocation is '$dmi'; set it to true or omit it"
      user_invoked=0
      ;;
  esac

  if [ "$user_invoked" -eq 1 ]; then
    if printf '%s' "$description" | grep -iq 'use when'; then
      fail "$at/SKILL.md: user-invoked, so the description is one human-facing line with no trigger phrasing"
    fi
  elif ! printf '%s' "$description" | grep -iq 'use when'; then
    fail "$at/SKILL.md: model-invoked, so the description needs trigger phrasing (\"Use when the user…\")"
  fi

  if [ ! -f "$yaml" ]; then
    fail "$at: no agents/openai.yaml"
  else
    grep -q '^interface:' "$yaml" || fail "$at/agents/openai.yaml: no interface: block"
    [ -n "$(yaml_value display_name "$yaml")" ] ||
      fail "$at/agents/openai.yaml: no interface.display_name"
    [ -n "$(yaml_value short_description "$yaml")" ] ||
      fail "$at/agents/openai.yaml: no interface.short_description"

    implicit="$(yaml_value allow_implicit_invocation "$yaml")"
    has_policy=0
    grep -q '^policy:' "$yaml" && has_policy=1
    if [ "$user_invoked" -eq 1 ] && [ "$implicit" != false ]; then
      fail "$at: user-invoked in SKILL.md, but agents/openai.yaml lacks policy.allow_implicit_invocation: false"
    elif [ "$user_invoked" -eq 0 ] && [ "$has_policy" -eq 1 ]; then
      fail "$at: model-invoked in SKILL.md, so agents/openai.yaml has no policy block"
    fi
  fi

  if ! grep -Fq "[\`$name\`](skills/$name/SKILL.md)" "$ROOT/README.md" 2>/dev/null; then
    fail "$at: no row in README.md's skill table"
  fi

  while IFS= read -r ref; do
    [ -e "$dir/$ref" ] || fail "$at/SKILL.md: points at \${CLAUDE_SKILL_DIR}/$ref, which doesn't exist"
  done < <(grep -o '\${CLAUDE_SKILL_DIR}/[^"`'"'"' )]*' "$skill" | sed 's|^\${CLAUDE_SKILL_DIR}/||' | sort -u)

  if [ -d "$dir/scripts" ] && [ -n "$(ls -A "$dir/scripts")" ] &&
     ! ls "$dir"/tests/*.test.sh >/dev/null 2>&1; then
    fail "$at: has scripts/ but no tests/*.test.sh"
  fi

  lines="$(wc -l < "$skill" | tr -d ' ')"
  if [ "$lines" -gt "$MAX_LINES" ]; then
    warn "$at/SKILL.md: $lines lines; past $MAX_LINES, move detail into references/ and point at it"
  fi
done

while IFS= read -r link; do
  [ -f "$ROOT/$link" ] || fail "README.md: links $link, which doesn't exist"
done < <(grep -o '](skills/[^)]*/SKILL.md)' "$ROOT/README.md" 2>/dev/null | sed -e 's/^](//' -e 's/)$//')

while IFS= read -r test; do
  test="${test#"$ROOT"/}"
  grep -Fq "bash $test\`" "$ROOT/CLAUDE.md" 2>/dev/null ||
    fail "$test: not listed under the tests in CLAUDE.md"
done < <(find "$ROOT" -maxdepth 1 -name '*.test.sh'; find "$ROOT/skills" -path '*/tests/*.test.sh' 2>/dev/null)

if [ "$fails" -gt 0 ]; then
  echo "$fails failed"
  exit 1
fi
echo "ok"
