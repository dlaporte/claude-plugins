#!/usr/bin/env bash
# Prints the version a plugin manifest declares, and exits 0, when it is a
# plain MAJOR.MINOR.PATCH string (scripts/semver.sh's SEMVER_TRIPLE, which
# says why that shape). Otherwise it prints nothing and exits 1: a missing or
# unreadable manifest, a missing or null version, a number, a v prefix, a
# pre-release or build suffix, a field of ten digits or more, or whitespace
# anywhere in the string, a trailing newline included. Whitespace
# is refused although compareSemver trims it: CLAUDE.md allows the plain
# triple only. The read is semver.sh's semver_json, whose header says why it
# reads JSON rather than raw text.
#
# scripts/check-manifests.sh, scripts/check-plugin-floor.sh and
# scripts/version-bump.sh read a plugin's version through this script.
# Usage: bash scripts/plugin-version.sh <path to plugin.json>
set -euo pipefail
export LC_ALL=C
# shellcheck source=scripts/semver.sh
. "$(cd "$(dirname "$0")" && pwd)/semver.sh"

manifest="${1:-}"
if [ -z "$manifest" ]; then
  echo "usage: bash scripts/plugin-version.sh <path to plugin.json>" >&2
  exit 2
fi

semver_json "$manifest" .version || exit 1
