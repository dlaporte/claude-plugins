#!/usr/bin/env bash
# Runs scripts/check-build-tools.sh on records and starters this script plants
# in a temporary directory, and fails unless each exit status and output is
# what the case calls for:
#   - a matching pair passes, and the starter's other devDependencies do not
#     matter;
#   - a moved esbuild fails naming esbuild alone;
#   - a tool the starter lacks fails naming it, and two moved tools give two
#     lines;
#   - a record without behavior.buildTools, or with an empty one, fails;
#   - an unreadable record or starter exits 2.
# Usage (from the repo root): bash scripts/test-check-build-tools.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/test-lib.sh
. "$here/test-lib.sh"
check="$here/check-build-tools.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
record="$tmp/record.json"
starter="$tmp/package.json"

# build_tools <record JSON> <starter devDependencies JSON>: the check, on a
# record and a starter planted with them.
build_tools() {
  printf '%s\n' "$1" >"$record"
  printf '{"devDependencies":%s}\n' "$2" >"$starter"
  bash "$check" "$starter" "$record"
}
# pair <name> <record JSON> <starter devDependencies JSON> <exit> <output>
pair() {
  expect "$1" "$4" "$5" build_tools "$2" "$3"
}

rec='{"pinned":{"ref":"vtest"},"behavior":{"buildTools":{"esbuild":"0.28.1","wrangler":"4.148.0"}}}'
ok='check-build-tools: OK (the starter'"'"'s build tools are the platform'"'"'s at vtest)'
line() { echo "check-build-tools: FAIL, $1: the starter pins $2, the platform builds with $3 (at vtest). Move the starter's devDependencies to the record's."; }

pair "a matching pair" "$rec" '{"esbuild":"0.28.1","wrangler":"4.148.0","react":"1"}' 0 "$ok"
pair "a moved esbuild" "$rec" '{"esbuild":"0.28.2","wrangler":"4.148.0"}' 1 "$(line esbuild 0.28.2 0.28.1)"
pair "a missing tool" "$rec" '{"esbuild":"0.28.1"}' 1 "$(line wrangler nothing 4.148.0)"
pair "two moved tools" "$rec" '{"esbuild":"0.1.0","wrangler":"4.0.0"}' 1 "$(line esbuild 0.1.0 0.28.1)
$(line wrangler 4.0.0 4.148.0)"
none='check-build-tools: FAIL, the pinned record names no build tools: pin a platform release from v0.18.5 on'
pair "a record without the field" '{"pinned":{"ref":"vtest"},"behavior":{}}' '{"esbuild":"0.28.1"}' 1 "$none"
pair "an empty field" '{"pinned":{"ref":"vtest"},"behavior":{"buildTools":{}}}' '{"esbuild":"0.28.1"}' 1 "$none"
pair "a record that is not JSON" 'nope' '{}' 2 "check-build-tools: $record is not readable JSON"
unreadable_starter() {
  printf '%s\n' "$rec" >"$record"
  printf 'nope\n' >"$starter"
  bash "$check" "$starter" "$record"
}
expect "a starter that is not JSON" 2 "check-build-tools: $starter is not readable JSON" unreadable_starter

[ "$fail" -eq 0 ] || exit 1
echo "test-check-build-tools: OK ($n cases: a matching pair passes; each moved or missing tool is named, a record with no build tools fails, and an unreadable record or starter is refused, each with exactly its message)"
