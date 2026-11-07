#!/usr/bin/env bash
# Fails if any file under either plugin, or any of the repository's other
# public text (its README.md and CLAUDE.md, the marketplace catalog users read
# at install, the CI workflow under .github, and scripts/, whose messages
# operators read in CI's logs), holds an em dash (U+2014) or an en dash
# (U+2013). That text uses a colon, a semicolon, a comma or a pair of
# parentheses instead, as the platform's served documents do.
# Usage: scripts/check-dashes.sh [path ...]
#   (default plugins/innovation-platform plugins/servicenow README.md
#   CLAUDE.md .claude-plugin/marketplace.json .github scripts; a path is a
#   directory, searched whole, or a file)
# Prints file:line: <line> for every line that holds one and exits 1 if there
# is any.
#
# The match is by bytes (e2 80 94 and e2 80 93, their UTF-8 forms) under
# LC_ALL=C, as two fixed strings rather than one alternation, so BSD and GNU
# grep read it alike and no locale can fold the characters away.
# scripts/test-check-dashes.sh plants each one and proves this catches it.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$here/lib.sh"

if [ $# -gt 0 ]; then
  targets=("$@")
else
  targets=(plugins/innovation-platform plugins/servicenow README.md CLAUDE.md
    .claude-plugin/marketplace.json .github scripts)
fi
for target in "${targets[@]}"; do
  if [ ! -e "$target" ]; then
    echo "check-dashes: no such file or directory: $target" >&2
    exit 2
  fi
done
named="$(join_names "${targets[@]}")"

em=$'\xe2\x80\x94'
en=$'\xe2\x80\x93'

hits="$(LC_ALL=C grep_or_none -rnHIF -e "$em" -e "$en" -- "${targets[@]}")"
if [ -n "$hits" ]; then
  # By file, then by line number, so the report reads the same on any grep.
  printf '%s\n' "$hits" | LC_ALL=C sort -t: -k1,1 -k2,2n
  echo "check-dashes: FAIL, an em dash (U+2014) or en dash (U+2013) is in $named. Use a colon, a semicolon, a comma or parentheses instead." >&2
  exit 1
fi
echo "check-dashes: OK ($named)"
