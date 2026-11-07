# shellcheck shell=bash disable=SC2154
# Sourced, never run: the skills and the source that
# scripts/test-check-version-gate.sh and scripts/test-render-gates.sh plant,
# so the two tests plant one shape. Each function writes under the test's
# $tmp, which the test sets before it calls one (so shellcheck, reading this
# file alone, is told not to look for it here); a test sources this before
# it sets its EXIT trap, as it does scripts/test-lib.sh.
#
#   block                  the planted source block, six lines: the heading,
#                          two steps and "Carry on."
#   skill <name>           a skill's text, holding block's lines at lines 7
#                          to 12, between front matter and a closing line
#   skills <tree>          $tmp/<tree>/source.md (block) and three skills,
#                          skills/a, skills/b and skills/c, each SKILL.md
#   edit <tree> <file> <sed program>
#                          one planted file under $tmp/<tree>, edited in place

block() {
  printf '%s\n' '## Version gate: do this first' '' '1. Read the version.' '2. Call the tool with it.' '' 'Carry on.'
}

skill() {
  printf '%s\n' --- "name: $1" --- '' "# $1" ''
  block
  printf '%s\n' '' "The skill's own steps."
}

skills() {
  local name
  mkdir -p "$tmp/$1"
  block >"$tmp/$1/source.md"
  for name in a b c; do
    mkdir -p "$tmp/$1/skills/$name"
    skill "$name" >"$tmp/$1/skills/$name/SKILL.md"
  done
}

edit() {
  sed "$3" "$tmp/$1/$2" >"$tmp/$1/$2.new"
  mv -f "$tmp/$1/$2.new" "$tmp/$1/$2"
}
