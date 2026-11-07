#!/usr/bin/env bash
# Fails if the inno-convert-artifact starter's dev/build-ui.mjs names, in its
# header, another platform ci/build-ui.mjs than the pinned release's. The
# starter's file builds an app's interface locally the way the platform's
# CI builds it with ci/build-ui.mjs, and is a second implementation, not a
# copy, so it cannot be hashed against the platform's. Its header names the
# platform release, the commit and the sha256 of the ci/build-ui.mjs it was
# last diffed against; a release from v0.18.18 records that file's sha256 in
# its compatibility record's shipped key, which scripts/platform-compat.json
# pins. A platform change to the file moves the hash, the resync prints it
# (scripts/platform-compat.sh), and this check fails until the starter is
# diffed against the new file, changed to match, and its header moved.
# scripts/test-build-parity.sh then builds one corpus with both builders and
# compares what they write.
#
# The header is the file's leading // lines; it must hold exactly one sha256
# (64 lowercase hex digits), which is compared with the record's
# shipped["ci/build-ui.mjs"]. scripts/test-check-starter-builder.sh runs this
# on builders and records it plants.
#
# Usage: bash scripts/check-starter-builder.sh [builder] [record]
#   (default plugins/innovation-platform/skills/inno-convert-artifact/assets/starter/app/dev/build-ui.mjs
#   and scripts/platform-compat.json)
# Exits 0 when the header's sha256 is the record's, 1 when it differs, the
# header names none or two, or the record holds none, and 2 when a file
# cannot be read.
set -euo pipefail
export LC_ALL=C
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$here/lib.sh"
require_jq

root="$(cd "$here/.." && pwd)"
builder="${1:-$root/plugins/innovation-platform/skills/inno-convert-artifact/assets/starter/app/dev/build-ui.mjs}"
record="${2:-$here/platform-compat.json}"
builder_name="${builder#"$PWD"/}"
record_name="${record#"$PWD"/}"
mirrored="ci/build-ui.mjs"

if ! jq -e . "$record" >/dev/null 2>&1; then
  echo "check-starter-builder: $record_name is not readable JSON" >&2
  exit 2
fi
if [ ! -f "$builder" ] || [ ! -r "$builder" ]; then
  echo "check-starter-builder: cannot read $builder_name" >&2
  exit 2
fi
pin="$(jq -r '.pinned.ref // "an unpinned record"' "$record")"
if ! want="$(jq -er --arg f "$mirrored" '.shipped[$f] | select(type == "string" and test("^[0-9a-f]{64}$"))' "$record" 2>/dev/null)"; then
  echo "check-starter-builder: FAIL, $record_name ($pin) holds no sha256 for $mirrored under shipped: pin a platform release from v0.18.18 on" >&2
  exit 1
fi

# The leading // lines, then every run of 64 hex digits in them standing alone.
header="$(awk '!/^\/\//{exit} {print}' "$builder")"
hashes="$(printf '%s\n' "$header" | grep_or_none -oE '(^|[^0-9a-f])[0-9a-f]{64}([^0-9a-f]|$)' | grep_or_none -oE '[0-9a-f]{64}')"
if [ -z "$hashes" ] || [ "$(printf '%s\n' "$hashes" | wc -l | tr -d ' ')" -ne 1 ]; then
  echo "check-starter-builder: FAIL, the header of $builder_name names $([ -z "$hashes" ] && echo "no" || echo "more than one") sha256 of the platform's $mirrored; it names one, the hash of the file it mirrors" >&2
  exit 1
fi

if [ "$hashes" != "$want" ]; then
  echo "check-starter-builder: FAIL, $builder_name mirrors the $mirrored whose sha256 is $hashes (its header), and the record at $pin holds $want. Diff it against the platform's $mirrored at $pin, change it to match, and move its header's release, commit and sha256; then run bash scripts/test-build-parity.sh." >&2
  exit 1
fi
echo "check-starter-builder: OK ($builder_name mirrors the $mirrored the record at $pin holds)"
