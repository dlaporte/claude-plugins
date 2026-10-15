#!/usr/bin/env bash
# Runs scripts/check-dashes.sh on trees this script plants in a temporary
# directory, and fails unless the check's whole output and exit status are
# exactly what each tree calls for:
#   - a clean tree passes: ASCII hyphens, a double hyphen, a minus sign
#     (U+2212) and a figure dash (U+2012) are not what the check bans;
#   - one em dash (U+2014) in a nested file fails, naming that file:line;
#   - one en dash (U+2013) in a dotfile fails, naming that file:line;
#   - both at once fail, naming both, and nothing else.
# Every planted character is built from its bytes with printf, so this file
# holds none of them itself.
# Usage (from the repo root): bash scripts/test-check-dashes.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
check="$here/check-dashes.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# plant <tree> <relative path> <printf format>: one file, written by bytes.
plant() {
  mkdir -p "$(dirname "$tmp/$1/$2")"
  # shellcheck disable=SC2059
  printf "$3" >"$tmp/$1/$2"
}
# The clean files every tree carries.
clean_tree() {
  plant "$1" README.md 'title\n\nA well-known pre-flight check -- and a minus \xe2\x88\x92 1.\n'
  plant "$1" skills/demo/SKILL.md 'line one\nA figure dash \xe2\x80\x92 is not banned.\n'
}
fail=0
# expect <label> <tree> <expected exit> <expected output>
expect() {
  local rc=0 out
  out="$(cd "$tmp" && bash "$check" "$2" 2>&1)" || rc=$?
  if [ "$rc" -ne "$3" ] || [ "$out" != "$4" ]; then
    echo "test-check-dashes: $1: the check exited $rc (expected $3), and its output differs:" >&2
    diff <(printf '%s\n' "$4") <(printf '%s\n' "$out") >&2 || true
    fail=1
  fi
}
em=$'\xe2\x80\x94'
en=$'\xe2\x80\x93'
refusal="check-dashes: FAIL, an em dash (U+2014) or en dash (U+2013) is in"
remedy="Use a colon, a semicolon, a comma or parentheses instead."

clean_tree clean
expect "a clean tree" clean 0 "check-dashes: OK (clean)"

clean_tree em
plant em skills/demo/references/note.md 'first\nsecond \xe2\x80\x94 third\n'
expect "one em dash" em 1 "$(
  echo "em/skills/demo/references/note.md:2:second $em third"
  echo "$refusal em. $remedy"
)"

clean_tree en
plant en .claude-plugin/plugin.json '{"description":"pages 1\xe2\x80\x932"}\n'
expect "one en dash" en 1 "$(
  echo "en/.claude-plugin/plugin.json:1:{\"description\":\"pages 1${en}2\"}"
  echo "$refusal en. $remedy"
)"

clean_tree both
plant both b.md 'ok\nok\n1\xe2\x80\x932\n'
plant both a.md 'x \xe2\x80\x94 y\n'
expect "both dashes" both 1 "$(
  echo "both/a.md:1:x $em y"
  echo "both/b.md:3:1${en}2"
  echo "$refusal both. $remedy"
)"

expect "a missing directory" absent 2 "check-dashes: no such directory: absent"

[ "$fail" -eq 0 ] || exit 1
echo "test-check-dashes: OK (a clean tree with look-alikes passes; an em dash, an en dash and both are each reported by file:line, nothing else)"
