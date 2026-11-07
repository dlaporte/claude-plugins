#!/usr/bin/env bash
# Runs scripts/check-starter-builder.sh on builders and records this script
# plants in a temporary directory, and fails unless each exit status and
# output is what the case calls for:
#   - a header naming the record's sha256 passes, whatever else it says, and
#     a hash below the header is not read;
#   - a record whose hash moved fails, naming both hashes and what to do;
#   - a header naming no sha256, or two, fails, and so does a hash run into
#     other hex digits (65 of them);
#   - a record with no shipped key, or none for ci/build-ui.mjs, or one that
#     is not a sha256, fails, naming the release the key comes in;
#   - an unreadable record or builder exits 2.
# Usage (from the repo root): bash scripts/test-check-starter-builder.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/test-lib.sh
. "$here/test-lib.sh"
check="$here/check-starter-builder.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
record="$tmp/record.json"
builder="$tmp/build-ui.mjs"

h1=1111111111111111111111111111111111111111111111111111111111111111
h2=2222222222222222222222222222222222222222222222222222222222222222

# starter_builder <record JSON> <builder text>: the check, on a record and a
# builder planted with them.
starter_builder() {
  printf '%s\n' "$1" >"$record"
  printf '%s\n' "$2" >"$builder"
  bash "$check" "$builder" "$record"
}
rec() { printf '{"pinned":{"ref":"vtest"},"shipped":{"ci/build-ui.mjs":"%s"}}' "$1"; }
code='import { build } from "esbuild";'
# head <hash line>: a header in the starter's shape around one line.
head_with() {
  printf '%s\n' "// Local builds only." "//" "// It mirrors the platform's ci/build-ui.mjs at platform v9.9.9, where that" "// file last changed in abcdef12 and has the sha256" "// $1: the same build." "//" "// Usage (in app/): node dev/build-ui.mjs"
}
ok="check-starter-builder: OK ($builder mirrors the ci/build-ui.mjs the record at vtest holds)"
none_or_two() {
  echo "check-starter-builder: FAIL, the header of $builder names $1 sha256 of the platform's ci/build-ui.mjs; it names one, the hash of the file it mirrors"
}
no_record_hash="check-starter-builder: FAIL, $record (vtest) holds no sha256 for ci/build-ui.mjs under shipped: pin a platform release from v0.18.18 on"

expect "a header naming the record's sha256" 0 "$ok" starter_builder "$(rec "$h1")" "$(head_with "$h1")
$code"
expect "a hash below the header is not read" 0 "$ok" starter_builder "$(rec "$h1")" "$(head_with "$h1")
$code
// $h2"
expect "a record whose hash moved" 1 \
  "check-starter-builder: FAIL, $builder mirrors the ci/build-ui.mjs whose sha256 is $h1 (its header), and the record at vtest holds $h2. Diff it against the platform's ci/build-ui.mjs at vtest, change it to match, and move its header's release, commit and sha256; then run bash scripts/test-build-parity.sh." \
  starter_builder "$(rec "$h2")" "$(head_with "$h1")
$code"
expect "a header naming no sha256" 1 "$(none_or_two no)" starter_builder "$(rec "$h1")" "// Local builds only.
$code
// $h1"
expect "a header naming two" 1 "$(none_or_two "more than one")" starter_builder "$(rec "$h1")" "$(head_with "$h1")
// and $h2
$code"
expect "a hash run into other hex digits" 1 "$(none_or_two no)" starter_builder "$(rec "$h1")" "$(head_with "${h1}a")
$code"
expect "a record with no shipped key" 1 "$no_record_hash" starter_builder '{"pinned":{"ref":"vtest"},"served":{}}' "$(head_with "$h1")
$code"
expect "a record whose shipped key has no entry for ci/build-ui.mjs" 1 "$no_record_hash" \
  starter_builder '{"pinned":{"ref":"vtest"},"shipped":{"ci/fixtures/template/scaffold/function/app/identity.ts":"'"$h1"'"}}' "$(head_with "$h1")
$code"
expect "a record whose entry is not a sha256" 1 "$no_record_hash" starter_builder "$(rec "${h1%?}")" "$(head_with "$h1")
$code"
expect "a record that is not JSON" 2 "check-starter-builder: $record is not readable JSON" starter_builder 'nope' "$code"
missing_builder() {
  printf '%s\n' "$(rec "$h1")" >"$record"
  bash "$check" "$tmp/absent.mjs" "$record"
}
expect "a missing builder" 2 "check-starter-builder: cannot read $tmp/absent.mjs" missing_builder

[ "$fail" -eq 0 ] || exit 1
echo "test-check-starter-builder: OK ($n cases: a header naming the record's sha256 passes; a moved hash fails with both; a header naming none or two, and a record with no sha256 for ci/build-ui.mjs, fail; an unreadable record or builder is refused, each with exactly its message)"
