#!/usr/bin/env bash
# Fails if any file under the innovation-platform plugin, or any of the
# repository's other public text (its README.md and CLAUDE.md, and the
# marketplace catalog users read at install), holds an em dash (U+2014) or an
# en dash (U+2013). That prose uses a colon, a semicolon, a comma or a pair of
# parentheses instead, as the platform's served documents do.
# Usage: scripts/check-dashes.sh [path ...]
#   (default plugins/innovation-platform README.md CLAUDE.md
#   .claude-plugin/marketplace.json; a path is a directory, searched whole, or
#   a file)
# Prints file:line: <line> for every line that holds one and exits 1 if there
# is any.
#
# The match is by bytes (e2 80 94 and e2 80 93, their UTF-8 forms) under
# LC_ALL=C, as two fixed strings rather than one alternation, so BSD and GNU
# grep read it alike and no locale can fold the characters away.
# scripts/test-check-dashes.sh plants each one and proves this catches it.
set -euo pipefail

if [ $# -gt 0 ]; then
  targets=("$@")
else
  targets=(plugins/innovation-platform README.md CLAUDE.md .claude-plugin/marketplace.json)
fi
for target in "${targets[@]}"; do
  if [ ! -e "$target" ]; then
    echo "check-dashes: no such file or directory: $target" >&2
    exit 2
  fi
done
# The targets as the messages name them: "a, b and c".
named="${targets[0]}"
if [ "${#targets[@]}" -gt 1 ]; then
  named="$(printf '%s, ' "${targets[@]:0:${#targets[@]}-1}")"
  named="${named%, } and ${targets[${#targets[@]}-1]}"
fi

em=$'\xe2\x80\x94'
en=$'\xe2\x80\x93'

# grep exits 1 for "no match", which is the passing case here; 2 is an error.
rc=0
hits="$(LC_ALL=C grep -rnHIF -e "$em" -e "$en" -- "${targets[@]}")" || rc=$?
if [ "$rc" -gt 1 ]; then
  echo "check-dashes: grep failed ($rc)" >&2
  exit 2
fi
if [ "$rc" -eq 0 ]; then
  # By file, then by line number, so the report reads the same on any grep.
  printf '%s\n' "$hits" | LC_ALL=C sort -t: -k1,1 -k2,2n
  echo "check-dashes: FAIL, an em dash (U+2014) or en dash (U+2013) is in $named. Use a colon, a semicolon, a comma or parentheses instead." >&2
  exit 1
fi
echo "check-dashes: OK ($named)"
