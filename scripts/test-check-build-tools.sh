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
check="$here/check-build-tools.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
record="$tmp/record.json"
starter="$tmp/package.json"
fail=0

# expect <name> <record JSON> <starter devDependencies JSON> <exit> <output>
expect() {
  local rc=0 out
  printf '%s\n' "$2" >"$record"
  printf '{"devDependencies":%s}\n' "$3" >"$starter"
  out="$(bash "$check" "$starter" "$record" 2>&1)" || rc=$?
  if [ "$rc" -ne "$4" ] || [ "$out" != "$5" ]; then
    echo "test-check-build-tools: $1 exited $rc (expected $4), output:" >&2
    diff <(printf '%s\n' "$5") <(printf '%s\n' "$out") >&2 || true
    fail=1
  fi
}

rec='{"pinned":{"ref":"vtest"},"behavior":{"buildTools":{"esbuild":"0.28.1","wrangler":"4.148.0"}}}'
ok='check-build-tools: OK (the starter'"'"'s build tools are the platform'"'"'s at vtest)'
line() { echo "check-build-tools: FAIL, $1: the starter pins $2, the platform builds with $3 (at vtest). Move the starter's devDependencies to the record's."; }

expect "a matching pair" "$rec" '{"esbuild":"0.28.1","wrangler":"4.148.0","react":"1"}' 0 "$ok"
expect "a moved esbuild" "$rec" '{"esbuild":"0.28.2","wrangler":"4.148.0"}' 1 "$(line esbuild 0.28.2 0.28.1)"
expect "a missing tool" "$rec" '{"esbuild":"0.28.1"}' 1 "$(line wrangler nothing 4.148.0)"
expect "two moved tools" "$rec" '{"esbuild":"0.1.0","wrangler":"4.0.0"}' 1 "$(line esbuild 0.1.0 0.28.1)
$(line wrangler 4.0.0 4.148.0)"
none='check-build-tools: FAIL, the pinned record names no build tools: pin a platform release from v0.18.5 on'
expect "a record without the field" '{"pinned":{"ref":"vtest"},"behavior":{}}' '{"esbuild":"0.28.1"}' 1 "$none"
expect "an empty field" '{"pinned":{"ref":"vtest"},"behavior":{"buildTools":{}}}' '{"esbuild":"0.28.1"}' 1 "$none"
expect "a record that is not JSON" 'nope' '{}' 2 "check-build-tools: $record is not readable JSON"
rc=0
printf '%s\n' "$rec" >"$record"
printf 'nope\n' >"$starter"
out="$(bash "$check" "$starter" "$record" 2>&1)" || rc=$?
if [ "$rc" -ne 2 ] || [ "$out" != "check-build-tools: $starter is not readable JSON" ]; then
  echo "test-check-build-tools: an unreadable starter exited $rc, output: $out" >&2
  fail=1
fi

if [ "$fail" -ne 0 ]; then exit 1; fi
echo "test-check-build-tools: OK"
