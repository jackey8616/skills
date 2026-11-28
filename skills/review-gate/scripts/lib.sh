# Shared by stop-gate.sh and pre-bash.sh. Sourced, not run.

# A package manager verb that installs or fetches, at the start of a command
# or after ; & | ( ` or $( — so `grep "pip install" README` doesn't count and
# `cd x && pip install y` does. Extended regex.
_rg_verb='(^|[;&|(`]|\$\()[[:space:]]*(sudo[[:space:]]+)?((pip3?|uv[[:space:]]+pip|python3?[[:space:]]+-m[[:space:]]+pip)[[:space:]]+(install|download)|uv[[:space:]]+(add|sync)|uv[[:space:]]+tool[[:space:]]+install|poetry[[:space:]]+(add|install)|pipx[[:space:]]+install|conda[[:space:]]+install|npm[[:space:]]+(install|i|ci|add)|yarn[[:space:]]+(add|install)|pnpm[[:space:]]+(add|install|i)|gem[[:space:]]+install|bundle[[:space:]]+install|cargo[[:space:]]+(install|add)|go[[:space:]]+(get|install)|(apt|apt-get|brew|apk|dnf|yum)[[:space:]]+install)'
# The verb and the rest of its command, up to ; & | ) ` or the end of the line.
# The rest decides `pip download x --help`, which prints help and fetches nothing.
REVIEW_GATE_INSTALL_RE="$_rg_verb"'([[:space:]][^;&|)`]*)?([;&|)`]|$)'

# install_lines: commands on stdin; the lines with a command that installs or
# fetches on stdout. A command with -h or --help in it only prints help.
install_lines() {
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    printf '%s\n' "$line" | grep -oE -- "$REVIEW_GATE_INSTALL_RE" \
      | grep -qvE '[[:space:]](-h|--help)([[:space:];&|)`]|$)' && printf '%s\n' "$line"
  done
  return 0
}
