#!/usr/bin/env bash
# Fails if scripts/starter-test/identity.ts, below its header, is not the
# platform's function scaffold's app/identity.ts at the pinned release. The
# inno-convert-artifact starter imports ./identity from the scaffold that
# registration commits beside it (the skill's step 5), and the starter's
# suite type-checks and runs against this copy, since this repository's CI
# has no platform checkout. A release from v0.18.18 records that file's
# sha256 in its compatibility record's shipped key, which
# scripts/platform-compat.json pins, so a platform change to the file moves
# the hash, the resync prints it (scripts/platform-compat.sh), and this
# check fails until the copy is taken again.
#
# The header is every line up to and including the first empty one, and its
# first line must be a // comment; it names no release of its own, since the
# record names the one it is held to. Everything below it is hashed whole
# (every byte, the last newline included) and compared with the record's
# shipped["ci/fixtures/template/scaffold/function/app/identity.ts"].
# scripts/test-check-scaffold-copy.sh runs this on copies and records it
# plants.
#
# Usage: bash scripts/check-scaffold-copy.sh [copy] [record]
#   (default scripts/starter-test/identity.ts and scripts/platform-compat.json)
# Exits 0 when the copy is the record's, 1 when it differs or the record
# holds no hash for the file, and 2 when a file cannot be read or the copy
# has no header.
set -euo pipefail
export LC_ALL=C
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$here/lib.sh"
require_jq

copy="${1:-$here/starter-test/identity.ts}"
record="${2:-$here/platform-compat.json}"
copy_name="${copy#"$PWD"/}"
record_name="${record#"$PWD"/}"
scaffold="ci/fixtures/template/scaffold/function/app/identity.ts"

if ! jq -e . "$record" >/dev/null 2>&1; then
  echo "check-scaffold-copy: $record_name is not readable JSON" >&2
  exit 2
fi
if [ ! -f "$copy" ] || [ ! -r "$copy" ]; then
  echo "check-scaffold-copy: cannot read $copy_name" >&2
  exit 2
fi
pin="$(jq -r '.pinned.ref // "an unpinned record"' "$record")"
if ! want="$(jq -er --arg f "$scaffold" '.shipped[$f] | select(type == "string" and test("^[0-9a-f]{64}$"))' "$record" 2>/dev/null)"; then
  echo "check-scaffold-copy: FAIL, $record_name ($pin) holds no sha256 for $scaffold under shipped: pin a platform release from v0.18.18 on" >&2
  exit 1
fi

end="$(grep_or_none -n -m1 '^$' "$copy" | cut -d: -f1)"
if [ -z "$end" ] || [ "$(head -c 2 "$copy")" != "//" ]; then
  echo "check-scaffold-copy: $copy_name has no header (// comment lines ended by an empty line) to read below" >&2
  exit 2
fi
have="$(tail -n +"$((end + 1))" "$copy" | sha256_of)"

if [ "$have" != "$want" ]; then
  echo "check-scaffold-copy: FAIL, $copy_name below its header (line $((end + 1)) on) hashes to $have, and $scaffold at $pin to $want. Copy the platform's file at $pin below the header again, then run the starter's suite (bash scripts/test-starter.sh)." >&2
  exit 1
fi
echo "check-scaffold-copy: OK ($copy_name below its header is $scaffold at $pin)"
