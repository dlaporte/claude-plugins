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
# whole of skills/ must report exactly the planted lines and exit 1; passes/
# alone must exit 0.
# Both runs read the fixture's own record,
# scripts/fixtures/check-contract-sections/record.json, not the real pinned
# one, so a resync that renumbers the contract needs no fixture edit. It has
# a section the real contract does not ("8", which passes/ asks for), so the
# test also proves the check reads the record it is given.
# Usage (from the repo root): bash scripts/test-check-contract-sections.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
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

fail=0
rc=0
out="$(cd "$here/.." && bash scripts/check-contract-sections.sh "$fixture/skills" "$record" 2>/dev/null)" || rc=$?
if [ "$rc" -ne 1 ]; then
  echo "test-check-contract-sections: the check exited $rc on the fixture, expected 1" >&2
  fail=1
fi
if [ "$out" != "$expected" ]; then
  echo "test-check-contract-sections: the check reported something other than what the fixture plants:" >&2
  diff <(printf '%s\n' "$expected") <(printf '%s\n' "$out") >&2 || true
  fail=1
fi

# The passing file alone.
rc=0
out="$(cd "$here/.." && bash scripts/check-contract-sections.sh "$fixture/skills/passes" "$record" 2>&1)" || rc=$?
if [ "$rc" -ne 0 ]; then
  echo "test-check-contract-sections: the check exited $rc on passes/, expected 0:" >&2
  printf '%s\n' "$out" >&2
  fail=1
fi
[ "$fail" -eq 0 ] || exit 1
echo "test-check-contract-sections: OK ($(printf '%s\n' "$expected" | grep -c .) planted lines reported, nothing else; the look-alikes pass alone)"
