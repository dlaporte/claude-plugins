#!/usr/bin/env bash
# Runs scripts/check-contract-sections.sh on its fixture and fails unless its
# output and exit status are exactly what the fixture plants. The fixture,
# scripts/fixtures/check-contract-sections/skills/, holds fails/SKILL.md, one
# line per rule that must fail (an id the contract does not have, alone,
# among good ones, in a second literal on a line, under the JSON key and in a
# literal glued to the one before it; an element that is not a quoted string;
# a literal that does not close on its line; an id that is neither numbers
# joined by dots nor R and a number; a requirement id the contract does not
# have), fails/example.json, a bad id in a file that is not Markdown, and
# passes/SKILL.md, the look-alikes that must pass (valid ids, requirement ids
# among them, an id after the literal, a list with no sections key, a section
# sign in prose, an empty literal, a word that ends in sections, the key right
# after a bracket). The
# whole of skills/ must report exactly the planted lines and the failure
# that counts them, and exit 1; passes/ alone must pass with its OK line.
# Both runs read the fixture's own record,
# scripts/fixtures/check-contract-sections/record.json, not the real pinned
# one, so a resync that renumbers the contract needs no fixture edit. It has
# a section the real contract does not ("8", which passes/ asks for), so the
# test also proves the check reads the record it is given.
# Usage (from the repo root): bash scripts/test-check-contract-sections.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/test-lib.sh
. "$here/test-lib.sh"
fixture="scripts/fixtures/check-contract-sections"
record="$fixture/record.json"
file="$fixture/skills/fails/SKILL.md"
json="$fixture/skills/fails/example.json"

expected="$(cat <<EOF
$file:8: "9" is not a section of the pinned contract
$file:9: "2.9" is not a section of the pinned contract
$file:10: "0" is not a section of the pinned contract
$file:11: 2 is not a quoted section id
$file:12: "1.9" is not a section of the pinned contract
$file:13: a sections literal does not close on its line, so it cannot be read; keep it on one line
$file:15: "9" is not a section of the pinned contract
$file:16: "1.3 2" is not a section id: an id is numbers joined by dots, or R and a number
$file:17: "R9" is not a section of the pinned contract
$file:18: "r3" is not a section id: an id is numbers joined by dots, or R and a number
$file:19: "R3.1" is not a section id: an id is numbers joined by dots, or R and a number
$json:1: "9" is not a section of the pinned contract
EOF
)"
pinned="contract 1 at vfixture ($record)"
# sections <path>: the check on that path of the fixture, against its record,
# from the repository root.
sections() {
  cd "$here/.." && bash scripts/check-contract-sections.sh "$1" "$record"
}

expect "the whole fixture" 1 "$(
  printf '%s\n' "$expected"
  echo "check-contract-sections: FAIL, $(printf '%s\n' "$expected" | grep -c .) element(s) above are not sections of $pinned. Fix the id, or if the platform renumbered its contract, resync with scripts/platform-compat.sh and read the contract's history."
)" sections "$fixture/skills"
expect "the passing file alone" 0 \
  "check-contract-sections: OK ($fixture/skills/passes, 10 literal(s) asking for 21 section(s), all in contract 1 at vfixture)" \
  sections "$fixture/skills/passes"

[ "$fail" -eq 0 ] || exit 1
echo "test-check-contract-sections: OK ($(printf '%s\n' "$expected" | grep -c .) planted lines reported, nothing else; the look-alikes pass alone)"
