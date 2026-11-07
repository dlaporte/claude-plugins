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
#   - with no path, the check reads its seven default targets, the two
#     plugins, the README, CLAUDE.md, the marketplace catalog, .github and
#     scripts, and a dash under .github, scripts or plugins/servicenow fails;
#   - a missing path cannot be read (exit 2).
# Every planted character is built from its bytes with printf, so this file
# holds none of them itself.
# Usage (from the repo root): bash scripts/test-check-dashes.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/test-lib.sh
. "$here/test-lib.sh"
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
# dashes <path ...>: the check, run from the temporary directory.
dashes() {
  cd "$tmp" && bash "$check" "$@"
}
# defaults: the check with no path, run from the planted repository.
defaults() {
  cd "$tmp/defaults" && bash "$check"
}
em=$'\xe2\x80\x94'
en=$'\xe2\x80\x93'
refusal="check-dashes: FAIL, an em dash (U+2014) or en dash (U+2013) is in"
remedy="Use a colon, a semicolon, a comma or parentheses instead."

clean_tree clean
expect "a clean tree" 0 "check-dashes: OK (clean)" dashes clean

clean_tree em
plant em skills/demo/references/note.md 'first\nsecond \xe2\x80\x94 third\n'
expect "one em dash" 1 "$(
  echo "em/skills/demo/references/note.md:2:second $em third"
  echo "$refusal em. $remedy"
)" dashes em

clean_tree en
plant en .claude-plugin/plugin.json '{"description":"pages 1\xe2\x80\x932"}\n'
expect "one en dash" 1 "$(
  echo "en/.claude-plugin/plugin.json:1:{\"description\":\"pages 1${en}2\"}"
  echo "$refusal en. $remedy"
)" dashes en

clean_tree both
plant both b.md 'ok\nok\n1\xe2\x80\x932\n'
plant both a.md 'x \xe2\x80\x94 y\n'
expect "both dashes" 1 "$(
  echo "both/a.md:1:x $em y"
  echo "both/b.md:3:1${en}2"
  echo "$refusal both. $remedy"
)" dashes both

clean_tree several
plant several notes/CLAUDE.md 'ok\n'
plant several catalog.json '{"description":"a \xe2\x80\x94 b"}\n'
expect "several paths" 1 "$(
  echo "several/catalog.json:1:{\"description\":\"a $em b\"}"
  echo "$refusal several/skills, several/notes/CLAUDE.md and several/catalog.json. $remedy"
)" dashes several/skills several/notes/CLAUDE.md several/catalog.json
expect "several clean paths" 0 "check-dashes: OK (several/skills and several/README.md)" \
  dashes several/skills several/README.md

# The repository's default targets, each planted clean.
plant defaults plugins/innovation-platform/skills/demo/SKILL.md 'ok\n'
plant defaults plugins/servicenow/skills/demo/SKILL.md 'ok\n'
plant defaults README.md 'ok\n'
plant defaults CLAUDE.md 'ok\n'
plant defaults .claude-plugin/marketplace.json '{}\n'
plant defaults .github/workflows/ci.yml 'name: CI\n'
plant defaults scripts/check.sh '# ok\n'
targets="plugins/innovation-platform, plugins/servicenow, README.md, CLAUDE.md, .claude-plugin/marketplace.json, .github and scripts"
expect "no path: the seven default targets" 0 "check-dashes: OK ($targets)" defaults
plant defaults .github/workflows/ci.yml 'name: CI\n# a \xe2\x80\x94 b\n'
plant defaults scripts/check.sh '# 1\xe2\x80\x932\n'
plant defaults plugins/servicenow/skills/demo/SKILL.md 'x \xe2\x80\x94 y\n'
expect "no path: a dash under .github, scripts and plugins/servicenow" 1 "$(
  echo ".github/workflows/ci.yml:2:# a $em b"
  echo "plugins/servicenow/skills/demo/SKILL.md:1:x $em y"
  echo "scripts/check.sh:1:# 1${en}2"
  echo "$refusal $targets. $remedy"
)" defaults

expect "a missing path" 2 "check-dashes: no such file or directory: absent" dashes absent

[ "$fail" -eq 0 ] || exit 1
echo "test-check-dashes: OK ($n cases: a clean tree with look-alikes passes; an em dash, an en dash and both are each reported by file:line, nothing else, in one path, several or the seven default targets)"
