# Shared by stop-gate.sh and pre-bash.sh. Sourced, not run.

# A shell command that installs or fetches a package, at the start of a
# command or after ; & | ( or $( — so `grep "pip install" README` doesn't
# count, and `cd x && pip install y` does. Extended regex, matched per line.
REVIEW_GATE_INSTALL_RE='(^|[;&|(`]|\$\()[[:space:]]*(sudo[[:space:]]+)?((pip3?|uv[[:space:]]+pip|python3?[[:space:]]+-m[[:space:]]+pip)[[:space:]]+(install|download)|uv[[:space:]]+(add|sync)|uv[[:space:]]+tool[[:space:]]+install|poetry[[:space:]]+(add|install)|pipx[[:space:]]+install|conda[[:space:]]+install|npm[[:space:]]+(install|i|ci|add)|yarn[[:space:]]+(add|install)|pnpm[[:space:]]+(add|install|i)|gem[[:space:]]+install|bundle[[:space:]]+install|cargo[[:space:]]+(install|add)|go[[:space:]]+(get|install)|(apt|apt-get|brew|apk|dnf|yum)[[:space:]]+install)([[:space:]]|$)'

# install_lines: commands on stdin, the lines that install or fetch on stdout.
install_lines() { grep -E -- "$REVIEW_GATE_INSTALL_RE" || true; }
