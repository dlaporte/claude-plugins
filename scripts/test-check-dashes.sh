#!/usr/bin/env bash
# Runs scripts/check-dashes.sh on trees this script plants in a temporary
# directory, and fails unless the check's whole output and exit status are
# exactly what each tree calls for:
#   - a clean tree passes: ASCII hyphens, a double hyphen, a minus sign
#     (U+2212) and a figure dash (U+2012) are not what the check bans;
#   - one em dash (U+2014) in a nested file fails, naming that file:line;
#   - one en dash (U+2013) in a dotfile fails, naming that file:line;
#   - both at once fail, naming both, and nothing else;
#   - several paths at once, a directory and two files, are each read, and a
#     dash in one file fails naming it, the rest named in the message;
#   - a missing path cannot be read (exit 2).
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
# expect <label> <expected exit> <expected output> <path ...>
expect() {
  local rc=0 out label="$1" want_rc="$2" want="$3"
  shift 3
  out="$(cd "$tmp" && bash "$check" "$@" 2>&1)" || rc=$?
  if [ "$rc" -ne "$want_rc" ] || [ "$out" != "$want" ]; then
    echo "test-check-dashes: $label: the check exited $rc (expected $want_rc), and its output differs:" >&2
    diff <(printf '%s\n' "$want") <(printf '%s\n' "$out") >&2 || true
    fail=1
  fi
}
em=$'\xe2\x80\x94'
en=$'\xe2\x80\x93'
refusal="check-dashes: FAIL, an em dash (U+2014) or en dash (U+2013) is in"
remedy="Use a colon, a semicolon, a comma or parentheses instead."

clean_tree clean
expect "a clean tree" 0 "check-dashes: OK (clean)" clean

clean_tree em
plant em skills/demo/references/note.md 'first\nsecond \xe2\x80\x94 third\n'
expect "one em dash" 1 "$(
  echo "em/skills/demo/references/note.md:2:second $em third"
  echo "$refusal em. $remedy"
)" em

clean_tree en
plant en .claude-plugin/plugin.json '{"description":"pages 1\xe2\x80\x932"}\n'
expect "one en dash" 1 "$(
  echo "en/.claude-plugin/plugin.json:1:{\"description\":\"pages 1${en}2\"}"
  echo "$refusal en. $remedy"
)" en

clean_tree both
plant both b.md 'ok\nok\n1\xe2\x80\x932\n'
plant both a.md 'x \xe2\x80\x94 y\n'
expect "both dashes" 1 "$(
  echo "both/a.md:1:x $em y"
  echo "both/b.md:3:1${en}2"
  echo "$refusal both. $remedy"
)" both

clean_tree several
plant several notes/CLAUDE.md 'ok\n'
plant several catalog.json '{"description":"a \xe2\x80\x94 b"}\n'
expect "several paths" 1 "$(
  echo "several/catalog.json:1:{\"description\":\"a $em b\"}"
  echo "$refusal several/skills, several/notes/CLAUDE.md and several/catalog.json. $remedy"
)" several/skills several/notes/CLAUDE.md several/catalog.json
expect "several clean paths" 0 "check-dashes: OK (several/skills and several/README.md)" several/skills several/README.md

expect "a missing path" 2 "check-dashes: no such file or directory: absent" absent

[ "$fail" -eq 0 ] || exit 1
echo "test-check-dashes: OK (a clean tree with look-alikes passes; an em dash, an en dash and both are each reported by file:line, nothing else, in one path or several)"
