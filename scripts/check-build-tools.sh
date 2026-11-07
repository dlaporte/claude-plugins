#!/usr/bin/env bash
# Fails if the inno-convert-artifact starter's build tool pins are not the
# pinned platform release's. The platform's CI builds an app's interface with
# the tools in ci/build/package.json (wrangler, esbuild and the Tailwind CLI),
# and a release from v0.18.5 records them in its compatibility record as
# behavior.buildTools, which scripts/platform-compat.json pins. The starter's
# app/package.json lists the same tools in devDependencies, so a person's
# local build matches CI's.
#
# Only the record's tools are checked, against the starter's devDependencies
# of the same name, each pin compared as the exact string. The options stay
# the starter's copy: the starter's other devDependencies and its scripts are
# not the platform's to pin (Decision 20 of the v0.18.5 plan). Prints one line
# per tool whose starter pin differs (or is absent) and exits 1 if any does.
# scripts/test-check-build-tools.sh runs this on files it plants.
#
# Usage: bash scripts/check-build-tools.sh [starter package.json] [record]
#   (default plugins/innovation-platform/skills/inno-convert-artifact/assets/starter/app/package.json
#   and scripts/platform-compat.json)
# Exits 0 when every pin agrees, 1 when one differs or the record names no
# build tools, and 2 when a file cannot be read.
set -euo pipefail
export LC_ALL=C
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$here/lib.sh"
require_jq

starter="${1:-$here/../plugins/innovation-platform/skills/inno-convert-artifact/assets/starter/app/package.json}"
record="${2:-$here/platform-compat.json}"

if ! jq -e . "$record" >/dev/null 2>&1; then
  echo "check-build-tools: $record is not readable JSON" >&2
  exit 2
fi
if ! jq -e . "$starter" >/dev/null 2>&1; then
  echo "check-build-tools: $starter is not readable JSON" >&2
  exit 2
fi
if ! jq -e '(.behavior.buildTools // null) | type == "object" and length > 0' "$record" >/dev/null; then
  echo "check-build-tools: FAIL, the pinned record names no build tools: pin a platform release from v0.18.5 on" >&2
  exit 1
fi

pin="$(jq -r '.pinned.ref // "an unpinned record"' "$record")"
out="$(jq -r --slurpfile s "$starter" '
  .behavior.buildTools | to_entries[]
  | . as $t
  | ($s[0].devDependencies[$t.key] // null) as $have
  | select($have != $t.value)
  | "\($t.key): the starter pins \($have // "nothing"), the platform builds with \($t.value)"' "$record")"

if [ -n "$out" ]; then
  while IFS= read -r line; do
    echo "check-build-tools: FAIL, $line (at $pin). Move the starter's devDependencies to the record's." >&2
  done <<<"$out"
  exit 1
fi
echo "check-build-tools: OK (the starter's build tools are the platform's at $pin)"
