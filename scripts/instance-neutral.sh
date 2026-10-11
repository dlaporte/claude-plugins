#!/usr/bin/env bash
# Fails if the innovation-platform plugin names any one platform instance.
# The plugin asks for the platform address and reads every other value from
# the platform, so none of these may appear under plugins/innovation-platform/.
# Usage: scripts/instance-neutral.sh [path]   (default plugins/innovation-platform)
# Prints file:line: <match> for every hit and exits 1 if there is any.
set -euo pipefail

target="${1:-plugins/innovation-platform}"

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
)

if [ ! -d "$target" ]; then
  echo "instance-neutral: no such directory: $target" >&2
  exit 2
fi

fail=0
for p in "${patterns[@]}"; do
  # -I skips binary files; -o prints only the matched text.
  if hits="$(grep -rnioIE -e "$p" -- "$target")"; then
    while IFS= read -r line; do
      echo "$line  [pattern: $p]"
    done <<<"$hits"
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "instance-neutral: FAIL, the plugin names an instance value. Read it from get_platform_status instead." >&2
  exit 1
fi
echo "instance-neutral: OK ($target)"
