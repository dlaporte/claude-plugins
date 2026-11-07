#!/usr/bin/env bash
# Fails if the innovation-platform plugin, or the platform record vendored
# beside it, names any one platform instance. The plugin asks for the
# platform address and reads every other value from the platform, so none of
# these may appear under plugins/innovation-platform/, nor in
# scripts/platform-compat.json and scripts/platform-tools.txt, which are
# public too.
# Usage: scripts/instance-neutral.sh [path ...]
#   (default plugins/innovation-platform; a path is a directory, searched
#   whole, or a file. Name the vendored files one by one: scripts/ also holds
#   this script, whose patterns match themselves.)
# Prints file:line: <match> for every hit and exits 1 if there is any.
# scripts/test-instance-neutral.sh runs this on trees and files it plants.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$here/lib.sh"

if [ $# -gt 0 ]; then
  targets=("$@")
else
  targets=(plugins/innovation-platform)
fi

# One extended regex per line, so a future edit is a one-line change.
patterns=(
  'davidlaporte'
  'dlaporte/inno-'
  '7robots'
  'harvard'
  'huit'
  'inno-platform-admins'
  'inno-platform-ci'
  'inno-template'
  'prefixed with `inno-'
  'inno-` group'
  'inno-\{'
  'inno-<'
  '`inno-`'
  'inno-[a-z0-9]*-(users|open)\b'
)

for target in "${targets[@]}"; do
  if [ ! -e "$target" ]; then
    echo "instance-neutral: no such file or directory: $target" >&2
    exit 2
  fi
done
named="$(join_names "${targets[@]}")"

fail=0
for p in "${patterns[@]}"; do
  # -H names the file even when one file is given; -I skips binary files;
  # -o prints only the matched text.
  hits="$(grep_or_none -rHnioIE -e "$p" -- "${targets[@]}")"
  if [ -n "$hits" ]; then
    while IFS= read -r line; do
      echo "$line  [pattern: $p]"
    done <<<"$hits"
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "instance-neutral: FAIL, an instance value is in $named. A plugin reads it from get_platform_status instead." >&2
  exit 1
fi
echo "instance-neutral: OK ($named)"
