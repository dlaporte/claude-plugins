#!/usr/bin/env bash
# Prints the version a plugin manifest declares, and exits 0, when it is a
# plain MAJOR.MINOR.PATCH string (scripts/semver.sh's SEMVER_TRIPLE, which
# says why that shape). Otherwise it prints nothing and exits 1: a missing or unreadable manifest, a missing or null version, a number, a
# v prefix, a pre-release or build suffix, a field of ten digits or more, or
# whitespace anywhere in the string, a trailing newline included. Whitespace
# is refused although compareSemver trims it: CLAUDE.md allows the plain
# triple only.
#
# The version is read as JSON (jq -c), not raw (jq -r): a raw read inside
# $(...) loses a trailing newline and passes "1.2.3\n", and jq's own regex
# anchors match at a line end. Encoded, a newline stays the two characters \n,
# a number or null carries no quotes, and a manifest of two JSON documents
# reads as two lines, so only one quoted string whose inside is a triple
# passes below.
#
# CI's manifests job and scripts/version-bump.sh both read a version through
# this script. Usage: bash scripts/plugin-version.sh <path to plugin.json>
set -euo pipefail
export LC_ALL=C
# shellcheck source=scripts/semver.sh
. "$(cd "$(dirname "$0")" && pwd)/semver.sh"

manifest="${1:-}"
if [ -z "$manifest" ]; then
  echo "usage: bash scripts/plugin-version.sh <path to plugin.json>" >&2
  exit 2
fi

raw="$(jq -c '.version' "$manifest" 2>/dev/null)" || exit 1
[[ "$raw" =~ ^\"(.*)\"$ ]] || exit 1
version="${BASH_REMATCH[1]}"
[[ "$version" =~ $SEMVER_TRIPLE ]] || exit 1
printf '%s\n' "$version"
