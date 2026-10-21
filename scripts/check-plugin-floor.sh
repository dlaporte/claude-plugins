#!/usr/bin/env bash
# Fails if the innovation-platform plugin's version is below the app plugin
# floor of the pinned platform release: plugins.app.minVersion in
# scripts/platform-compat.json, the floor that release ships. A release that
# raises its floor above this plugin would stop every skill at its Version
# gate, so the plugin has to be resynced and bumped first.
#
# Both versions must be plain MAJOR.MINOR.PATCH triples; the plugin's is read
# through scripts/plugin-version.sh, as CI's manifests job reads it. They are
# compared by scripts/semver.sh's semver_at_least, field by field as numbers,
# so 2.10.0 is above 2.9.0.
# scripts/test-check-plugin-floor.sh runs this on records and manifests it
# plants.
#
# Usage: bash scripts/check-plugin-floor.sh [record] [manifest]
#   (default scripts/platform-compat.json and
#   plugins/innovation-platform/.claude-plugin/plugin.json)
# Exits 0 when the plugin is at or above the floor, 1 when it is below, and 2
# when either version cannot be read.
set -euo pipefail
export LC_ALL=C
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/semver.sh
. "$here/semver.sh"

if ! command -v jq >/dev/null; then
  echo "check-plugin-floor: jq is required" >&2
  exit 2
fi

record="${1:-$here/platform-compat.json}"
manifest="${2:-$here/../plugins/innovation-platform/.claude-plugin/plugin.json}"

if ! version="$(bash "$here/plugin-version.sh" "$manifest")"; then
  echo "check-plugin-floor: $manifest declares no plain MAJOR.MINOR.PATCH version" >&2
  exit 2
fi
# Read as JSON, as plugin-version.sh reads a version, so only one quoted
# triple passes.
floor="$(jq -c '.plugins.app.minVersion' "$record" 2>/dev/null)" || floor=""
if ! [[ "$floor" =~ ^\"(.*)\"$ ]] || ! [[ "${BASH_REMATCH[1]}" =~ $SEMVER_TRIPLE ]]; then
  echo "check-plugin-floor: $record holds no plain MAJOR.MINOR.PATCH plugins.app.minVersion" >&2
  exit 2
fi
floor="${floor:1:${#floor}-2}"
pin="$(jq -r '.pinned.ref // "an unpinned record"' "$record")"

if semver_at_least "$version" "$floor"; then
  echo "check-plugin-floor: OK (the plugin's $version is at least $floor, the app plugin floor at $pin)"
  exit 0
fi
echo "check-plugin-floor: FAIL, the plugin's $version is below $floor, the app plugin floor (plugins.app.minVersion) at $pin. Resync the plugin with that release and bump its version to at least $floor." >&2
exit 1
