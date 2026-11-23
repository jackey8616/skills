#!/usr/bin/env bash
# Install or upgrade jackey8616/skills into Claude Code and Codex. No clone.
#
#   curl -fsSL https://raw.githubusercontent.com/jackey8616/skills/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/jackey8616/skills/main/install.sh | bash -s -- --uninstall
#
# Re-run to upgrade. Nothing updates on its own.
#
# Each skill is copied into ~/.claude/skills and ~/.agents/skills. A manifest
# in each directory records which skills this script owns, so a skill removed
# or renamed upstream is removed here too, and directories it doesn't own are
# never touched.
#
# Env:
#   SKILLS_REF      branch, tag, or commit to install (default: main)
#   SKILLS_ARCHIVE  local .tar.gz to install from instead of GitHub (tests)
set -euo pipefail

REPO="jackey8616/skills"
REF="${SKILLS_REF:-main}"
DESTS=("$HOME/.claude/skills" "$HOME/.agents/skills")
MANIFEST=".jackey8616-skills"

mode=install
case "${1:-}" in
  "") ;;
  --uninstall) mode=uninstall ;;
  -h|--help) echo "usage: install.sh [--uninstall]   (SKILLS_REF=<ref> to pin)"; exit 0 ;;
  *) echo "unknown option: $1" >&2; exit 2 ;;
esac

# Skill names listed in a manifest, one per line.
owned() { [ -f "$1/$MANIFEST" ] && grep -v '^#' "$1/$MANIFEST" || true; }

if [ "$mode" = uninstall ]; then
  for dest in "${DESTS[@]}"; do
    [ -f "$dest/$MANIFEST" ] || continue
    echo "$dest"
    for name in $(owned "$dest"); do
      rm -rf "${dest:?}/$name"
      echo "  removed   $name"
    done
    rm -f "$dest/$MANIFEST"
  done
  echo "Uninstalled $REPO."
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if [ -n "${SKILLS_ARCHIVE:-}" ]; then
  sha="local"
  tar -xzf "$SKILLS_ARCHIVE" -C "$tmp"
else
  # Pin the ref to a commit so every destination gets the same tree.
  sha="$(curl -fsSL -H 'Accept: application/vnd.github.sha' \
    "https://api.github.com/repos/$REPO/commits/$REF" 2>/dev/null || true)"
  [ -n "$sha" ] || sha="$REF"
  curl -fsSL "https://codeload.github.com/$REPO/tar.gz/$sha" | tar -xz -C "$tmp"
fi
src="$(echo "$tmp"/*/skills)"
[ -d "$src" ] || { echo "error: no skills/ in $REPO@$sha" >&2; exit 1; }

names=()
for skill_md in "$src"/*/SKILL.md; do
  [ -f "$skill_md" ] || continue  # unmatched glob: no skills
  names+=("$(basename "$(dirname "$skill_md")")")
done

echo "Installing $REPO @ ${sha:0:7} (${#names[@]} skills)"

for dest in "${DESTS[@]}"; do
  mkdir -p "$dest"
  echo "$dest"
  previous="$(owned "$dest")"
  kept=()

  for name in ${names[@]+"${names[@]}"}; do
    target="$dest/$name"
    if [ -L "$target" ]; then
      # A hand-made symlink, e.g. from a local checkout. Take it over,
      # owned or not — diff would follow it and call it unchanged.
      rm "$target"
      cp -R "$src/$name" "$target"
      echo "  installed $name (replaced symlink)"
      kept+=("$name")
    elif printf '%s\n' "$previous" | grep -qx "$name"; then
      if diff -rq "$src/$name" "$target" >/dev/null 2>&1; then
        echo "  unchanged $name"
        kept+=("$name")
        continue
      fi
      rm -rf "$target"
      cp -R "$src/$name" "$target"
      echo "  upgraded  $name"
      kept+=("$name")
    elif [ -e "$target" ]; then
      echo "  skipped   $name — $target exists and isn't ours" >&2
      continue
    else
      cp -R "$src/$name" "$target"
      echo "  installed $name"
      kept+=("$name")
    fi
  done

  for name in $previous; do
    if ! printf '%s\n' ${names[@]+"${names[@]}"} | grep -qx "$name"; then
      rm -rf "${dest:?}/$name"
      echo "  removed   $name"
    fi
  done

  {
    echo "# $REPO @ $sha"
    for name in ${kept[@]+"${kept[@]}"}; do echo "$name"; done
  } > "$dest/$MANIFEST"
done

echo "Done. Start a new session to pick up changes."
