#!/usr/bin/env bash
# Runs scripts/render-gates.sh on skills and sources this script plants in a
# temporary directory, and fails unless its whole output, its exit status and
# the files it leaves are exactly what each case calls for:
#   - a skill whose block differs is rewritten from the source, byte for byte,
#     and nothing else in any skill moves;
#   - a second run rewrites nothing (the render is reproducible), and --check,
#     which runs scripts/check-version-gate.sh, then passes;
#   - --check on a skill that differs fails as that check does (exit 1) and
#     writes nothing;
#   - an edit to the source reaches every skill;
#   - a malformed block beside one that differs stops the render (exit 2):
#     the check's lines are printed and no skill is written.
# Usage (from the repo root): bash scripts/test-render-gates.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/test-lib.sh
. "$here/test-lib.sh"
render="$here/render-gates.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

block() {
  printf '%s\n' '## Version gate: do this first' '' '1. Read the version.' '2. Call the tool with it.' '' 'Carry on.'
}
# skill <name>: a skill that holds block()'s lines at lines 7 to 12.
skill() {
  printf '%s\n' --- "name: $1" --- '' "# $1" ''
  block
  printf '%s\n' '' "The skill's own steps."
}
# skills <tree>: a source and three skills (a, b, c), with a copy of each
# skill as it should be, under expected/.
skills() {
  local name
  mkdir -p "$tmp/$1/expected"
  block >"$tmp/$1/source.md"
  for name in a b c; do
    mkdir -p "$tmp/$1/skills/$name"
    skill "$name" >"$tmp/$1/skills/$name/SKILL.md"
    skill "$name" >"$tmp/$1/expected/$name.md"
  done
}
# edit <tree> <file> <sed program>: one planted file, edited in place.
edit() {
  sed "$3" "$tmp/$1/$2" >"$tmp/$1/$2.new"
  mv -f "$tmp/$1/$2.new" "$tmp/$1/$2"
}
# same <tree>: which skills are byte for byte what expected/ holds.
same() {
  local name out="same as expected:"
  for name in a b c; do
    if cmp -s "$tmp/$1/skills/$name/SKILL.md" "$tmp/$1/expected/$name.md"; then out="$out $name"; fi
  done
  printf '%s\n' "$out"
}
# render <tree> [--check]: the renderer on that tree, then same.
render() {
  local tree="$1" rc=0
  shift
  (cd "$tmp/$tree" && bash "$render" "$@" skills source.md) 2>&1 || rc=$?
  same "$tree"
  return "$rc"
}
ok="render-gates: OK (3 skills hold source.md's block;"

skills drift
edit drift skills/b/SKILL.md 's/^2\. Call the tool with it\.$/2. Call the tool./'
expect "--check on a skill that differs" 1 "$(
  echo "::error file=skills/b/SKILL.md,line=10::the gate block differs from source.md here (its line 4)"
  echo "check-version-gate: FAIL, a skill's Version gate above differs from source.md, its one source. Edit that file, never a skill's copy, and run bash scripts/render-gates.sh."
  echo "same as expected: a c"
)" render drift --check
expect "a skill that differs is rewritten" 0 "$(
  echo "render-gates: wrote skills/b/SKILL.md"
  echo "$ok 1 rewritten)"
  echo "same as expected: a b c"
)" render drift
expect "a second run rewrites nothing" 0 "$(
  echo "$ok 0 rewritten)"
  echo "same as expected: a b c"
)" render drift
expect "--check after a render" 0 "$(
  echo "check-version-gate: OK (3 skills each hold source.md's block, once)"
  echo "same as expected: a b c"
)" render drift --check

skills source
edit source source.md 's/^1\. Read the version\.$/1. Read the plugin version./'
for name in a b c; do edit source "expected/$name.md" 's/^1\. Read the version\.$/1. Read the plugin version./'; done
expect "an edit to the source reaches every skill" 0 "$(
  echo "render-gates: wrote skills/a/SKILL.md"
  echo "render-gates: wrote skills/b/SKILL.md"
  echo "render-gates: wrote skills/c/SKILL.md"
  echo "$ok 3 rewritten)"
  echo "same as expected: a b c"
)" render source

skills stuck
edit stuck skills/a/SKILL.md 's/^2\. Call the tool with it\.$/2. Call the tool./'
edit stuck skills/c/SKILL.md '12d'
expect "a malformed block stops the render" 2 "$(
  echo "::error file=skills/a/SKILL.md,line=10::the gate block differs from source.md here (its line 4)"
  echo "::error file=skills/c/SKILL.md,line=7::the gate block that starts here has no \"Carry on.\" line to end it"
  echo "check-version-gate: FAIL, a skill's gate block above cannot be read: each skill holds one, from its \"## Version gate\" heading to its \"Carry on.\" line. Restore the heading or the line, then run bash scripts/render-gates.sh."
  echo "render-gates: wrote nothing: the check above cannot locate every gate block."
  echo "same as expected: b"
)" render stuck

[ "$fail" -eq 0 ] || exit 1
echo "test-render-gates: OK ($n cases: a block that differs is rewritten from the source and nothing else moves; a second run rewrites nothing; --check is the gate check; a source edit reaches every skill; a malformed block stops the render before any write)"
