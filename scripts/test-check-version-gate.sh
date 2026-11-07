#!/usr/bin/env bash
# Runs scripts/check-version-gate.sh on skills and sources this script plants
# in a temporary directory, and fails unless the check's whole output and
# exit status are exactly what each calls for:
#   - three skills that each hold the source's block pass;
#   - a block that differs from the source fails (exit 1), naming the first
#     line that differs, and so does a block one line longer;
#   - a malformed block fails (exit 2): no "Carry on." line, no heading, the
#     block twice, and the same malformed edit in every skill (which a
#     comparison of the copies with each other would pass);
#   - a source that is not one block alone fails (exit 2): no "Carry on."
#     line, or a line before its heading;
#   - a directory with no skills cannot be read (exit 2).
# Usage (from the repo root): bash scripts/test-check-version-gate.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/test-lib.sh
. "$here/test-lib.sh"
# block, skill, skills <tree> and edit: the planted skills and source, one
# shape with scripts/test-render-gates.sh's.
# shellcheck source=scripts/fixtures/version-gate.sh
. "$here/fixtures/version-gate.sh"
check="$here/check-version-gate.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# gate <tree>: the check on that tree's skills and source.
gate() {
  cd "$tmp/$1" && bash "$check" skills source.md
}
drifted="check-version-gate: FAIL, a skill's Version gate above differs from source.md, its one source. Edit that file, never a skill's copy, and run bash scripts/render-gates.sh."
malformed="check-version-gate: FAIL, a skill's gate block above cannot be read: each skill holds one, from its \"## Version gate\" heading to its \"Carry on.\" line. Restore the heading or the line, then run bash scripts/render-gates.sh."
bad_source="check-version-gate: FAIL, source.md is not one gate block alone, from its \"## Version gate\" heading to its \"Carry on.\" line."
no_end='the gate block that starts here has no "Carry on." line to end it'

skills good
expect "three skills that hold the source's block" 0 \
  "check-version-gate: OK (3 skills each hold source.md's block, once)" gate good

skills differs
edit differs skills/b/SKILL.md 's/^2\. Call the tool with it\.$/2. Call the tool./'
expect "a block that differs" 1 "$(
  echo "::error file=skills/b/SKILL.md,line=10::the gate block differs from source.md here (its line 4)"
  echo "$drifted"
)" gate differs

skills longer
edit longer skills/c/SKILL.md '12i\
3. Stop.
'
expect "a block one line longer" 1 "$(
  echo "::error file=skills/c/SKILL.md,line=12::the gate block differs from source.md here (its line 6)"
  echo "$drifted"
)" gate longer

skills noend
edit noend skills/b/SKILL.md '12d'
expect "a block with no Carry on. line" 2 "$(
  echo "::error file=skills/b/SKILL.md,line=7::$no_end"
  echo "$malformed"
)" gate noend

skills nohead
edit nohead skills/b/SKILL.md '7d'
expect "a block with no heading" 2 "$(
  echo "::error file=skills/b/SKILL.md::no \"## Version gate\" heading, so no gate block"
  echo "$malformed"
)" gate nohead

skills twice
block >>"$tmp/twice/skills/a/SKILL.md"
expect "a block twice" 2 "$(
  echo "::error file=skills/a/SKILL.md,line=15::a second \"## Version gate\" heading: a file holds one gate block"
  echo "::error file=skills/a/SKILL.md,line=20::a \"Carry on.\" line outside the gate block: only its last line reads so"
  echo "$malformed"
)" gate twice

skills everywhere
for name in a b c; do edit everywhere "skills/$name/SKILL.md" '12d'; done
expect "the same malformed edit in every skill" 2 "$(
  echo "::error file=skills/a/SKILL.md,line=7::$no_end"
  echo "::error file=skills/b/SKILL.md,line=7::$no_end"
  echo "::error file=skills/c/SKILL.md,line=7::$no_end"
  echo "$malformed"
)" gate everywhere

skills sourcenoend
edit sourcenoend source.md '6d'
expect "a source with no Carry on. line" 2 "$(
  echo "::error file=source.md,line=1::$no_end"
  echo "$bad_source"
)" gate sourcenoend

skills sourcepreamble
edit sourcepreamble source.md '1i\
The gate:
'
expect "a source with a line before its heading" 2 "$(
  echo "::error file=source.md,line=1::a line before the heading: the source is the gate block alone"
  echo "$bad_source"
)" gate sourcepreamble

mkdir -p "$tmp/empty/skills"
block >"$tmp/empty/source.md"
expect "a directory with no skills" 2 "check-version-gate: no skills under skills" gate empty

[ "$fail" -eq 0 ] || exit 1
echo "test-check-version-gate: OK ($n cases: skills that hold the source's block pass; a block that differs is named by its first differing line; a malformed block, one in every skill, a malformed source and no skills are each refused with exactly their lines)"
