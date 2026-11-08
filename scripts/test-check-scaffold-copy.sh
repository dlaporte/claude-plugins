#!/usr/bin/env bash
# Runs scripts/check-scaffold-copy.sh on copies and records this script plants
# in a temporary directory, and fails unless each exit status and output is
# what the case calls for:
#   - the unchanged copy passes, and so does one whose header alone changed;
#   - one byte changed below the header fails, naming both hashes, and so
#     does a copy that lost its last newline;
#   - the suite's own scripts/starter-test/identity.ts passes against a record
#     holding the hash of its lines below the first empty one (cut by sed, not
#     the way the check cuts it), and fails with one byte changed there;
#   - a record with no shipped key, or none for the scaffold's identity.ts,
#     or one that is not a sha256, fails, naming the release the key comes in;
#   - a copy with no empty line, or whose first line is not a // comment, and
#     an unreadable record or copy, exit 2.
# The planted hashes are literals, worked out once from the planted bytes.
# Usage (from the repo root): bash scripts/test-check-scaffold-copy.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/test-lib.sh
. "$here/test-lib.sh"
# shellcheck source=scripts/lib.sh
. "$here/lib.sh"
check="$here/check-scaffold-copy.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
record="$tmp/record.json"
copy="$tmp/identity.ts"
scaffold="ci/fixtures/template/scaffold/function/app/identity.ts"

header='// A planted header, which names no release.
// Its second line.
'
body="// The body's own first comment, which is not the header.
export const x = 1;"
# sha256 of the body's bytes with its last newline, and of the same with
# x = 2.
body_hash=df120de9d73253903436c46187961deb9a24960efa944d194653dc2a68bef25b
moved_hash=78582a8ffd81bf0bf3ab52ebedc361314318918cc7c13a0986953a64802f73a2

# scaffold_copy <record JSON> <copy text> [printf format]: the check, on a
# record and a copy planted with them (the copy ends with a newline unless
# the format says otherwise).
scaffold_copy() {
  printf '%s\n' "$1" >"$record"
  # shellcheck disable=SC2059
  printf "${3:-%s\n}" "$2" >"$copy"
  bash "$check" "$copy" "$record"
}
rec() { printf '{"pinned":{"ref":"vtest"},"shipped":{"%s":"%s"}}' "$scaffold" "$1"; }
ok="check-scaffold-copy: OK ($copy below its header is $scaffold at vtest)"
differs() {
  echo "check-scaffold-copy: FAIL, $copy below its header (line 4 on) hashes to $1, and $scaffold at vtest to $body_hash. Copy the platform's file at vtest below the header again, then run the starter's suite (bash scripts/test-starter.sh)."
}
none() {
  echo "check-scaffold-copy: FAIL, $record ($1) holds no sha256 for $scaffold under shipped: pin a platform release from v0.18.18 on"
}
no_header="check-scaffold-copy: $copy has no header (// comment lines ended by an empty line) to read below"

expect "the unchanged copy" 0 "$ok" scaffold_copy "$(rec "$body_hash")" "$header
$body"
expect "a copy whose header alone changed" 0 "$ok" scaffold_copy "$(rec "$body_hash")" "// Another header, of another length, naming v9.9.9.
// Its second line.
$header
$body" '%s\n'
expect "one byte changed below the header" 1 "$(differs "$moved_hash")" \
  scaffold_copy "$(rec "$body_hash")" "$header
${body/x = 1/x = 2}"
expect "a copy that lost its last newline" 1 "$(differs "$(printf '%s' "$body" | sha256_of)")" \
  scaffold_copy "$(rec "$body_hash")" "$header
$body" '%s'

# The suite's own copy, against a record holding the hash of what follows its
# first empty line, then with one byte changed there.
real="$here/starter-test/identity.ts"
real_hash="$(sed '1,/^$/d' "$real" | sha256_of)"
real_pair() {
  printf '%s\n' "$(rec "$real_hash")" >"$record"
  bash "$check" "$1" "$record"
}
changed_real() {
  sed '$s/.$/#/' "$real" >"$copy"
  real_pair "$copy"
}
real_lines="$(grep -n -m1 '^$' "$real" | cut -d: -f1)"
expect "the suite's own copy" 0 \
  "check-scaffold-copy: OK (${real#"$PWD"/} below its header is $scaffold at vtest)" real_pair "$real"
expect "the suite's own copy with one byte changed below its header" 1 \
  "check-scaffold-copy: FAIL, $copy below its header (line $((real_lines + 1)) on) hashes to $(sed '1,/^$/d' "$real" | sed '$s/.$/#/' | sha256_of), and $scaffold at vtest to $real_hash. Copy the platform's file at vtest below the header again, then run the starter's suite (bash scripts/test-starter.sh)." \
  changed_real

expect "a record with no shipped key" 1 "$(none vtest)" \
  scaffold_copy '{"pinned":{"ref":"vtest"},"served":{}}' "$header
$body"
expect "a record whose shipped key has no entry for the scaffold" 1 "$(none vtest)" \
  scaffold_copy '{"pinned":{"ref":"vtest"},"shipped":{"ci/build-ui.mjs":"'"$body_hash"'"}}' "$header
$body"
expect "a record whose entry is not a sha256" 1 "$(none vtest)" scaffold_copy "$(rec "${body_hash%?}")" "$header
$body"
expect "an unpinned record" 1 "$(none "an unpinned record")" \
  scaffold_copy '{"shipped":{}}' "$header
$body"
expect "a copy with no empty line" 2 "$no_header" scaffold_copy "$(rec "$body_hash")" "$body"
expect "a copy whose first line is not a comment" 2 "$no_header" scaffold_copy "$(rec "$body_hash")" "export const y = 0;

$body"
expect "a record that is not JSON" 2 "check-scaffold-copy: $record is not readable JSON" \
  scaffold_copy 'nope' "$header
$body"
missing_copy() {
  printf '%s\n' "$(rec "$body_hash")" >"$record"
  bash "$check" "$tmp/absent.ts" "$record"
}
expect "a missing copy" 2 "check-scaffold-copy: cannot read $tmp/absent.ts" missing_copy

[ "$fail" -eq 0 ] || exit 1
echo "test-check-scaffold-copy: OK ($n cases: the unchanged copy passes, whatever its header says; one byte changed below the header, the suite's own copy's included, fails with both hashes; a record with no sha256 for the scaffold's identity.ts fails; a copy with no header and an unreadable record or copy are refused, each with exactly its message)"
