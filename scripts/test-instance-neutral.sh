#!/usr/bin/env bash
# Runs scripts/instance-neutral.sh on trees and files this script plants in a
# temporary directory, and fails unless the check's whole output and exit
# status are exactly what each calls for:
#   - a clean directory passes, and so do two clean files;
#   - an instance value in a nested file of a directory fails, naming that
#     file:line, the text matched and its pattern;
#   - a file given alone is read, and its hit is named by file:line too;
#   - of two files, the one with a hit is named, the two named in the
#     message;
#   - a missing path cannot be read (exit 2).
# Usage (from the repo root): bash scripts/test-instance-neutral.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/test-lib.sh
. "$here/test-lib.sh"
check="$here/instance-neutral.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# plant <relative path> <line>...: one file, one argument a line.
plant() {
  mkdir -p "$(dirname "$tmp/$1")"
  local path="$1"
  shift
  printf '%s\n' "$@" >"$tmp/$path"
}
# neutral <path ...>: the check, run from the temporary directory.
neutral() {
  cd "$tmp" && bash "$check" "$@"
}
refusal() {
  echo "instance-neutral: FAIL, an instance value is in $1. A plugin reads it from get_platform_status instead."
}

plant clean/skills/demo/SKILL.md "Read the template repository from get_platform_status." "Groups carry the instance's prefix."
expect "a clean directory" 0 "instance-neutral: OK (clean)" neutral clean

plant nested/skills/demo/SKILL.md "Read the template repository from get_platform_status." "Clone inno-template first."
expect "a hit in a nested file" 1 "$(
  echo "nested/skills/demo/SKILL.md:2:inno-template  [pattern: inno-template]"
  refusal nested
)" neutral nested

plant record.json '{"format":1,"owner":"huit-apps"}'
expect "a file given alone" 1 "$(
  echo "record.json:1:huit  [pattern: huit]"
  refusal record.json
)" neutral record.json

plant tools.txt "# tool names" "app_status" "list_apps"
expect "two files, one with a hit" 1 "$(
  echo "record.json:1:huit  [pattern: huit]"
  refusal "tools.txt and record.json"
)" neutral tools.txt record.json
plant other.txt "get_platform_status"
expect "two clean files" 0 "instance-neutral: OK (tools.txt and other.txt)" neutral tools.txt other.txt

expect "a missing path" 2 "instance-neutral: no such file or directory: absent" neutral absent

[ "$fail" -eq 0 ] || exit 1
echo "test-instance-neutral: OK ($n cases: clean directories and files pass; a hit in a directory or in a file given alone is named by file:line and pattern, nothing else; a missing path is refused)"
