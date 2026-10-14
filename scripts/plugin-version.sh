#!/usr/bin/env bash
# Prints the version a plugin manifest declares, and exits 0, when it is a
# plain MAJOR.MINOR.PATCH string with at most nine digits in each field: the
# shape CLAUDE.md allows, and one the Innovation Platform parses
# (compareSemver in inno-platform's src/util.ts reads \d{1,9} per field and
# answers anything else "unparseable"). Otherwise it prints nothing and exits
# 1: a missing or unreadable manifest, a missing or null version, a number, a
# v prefix, a pre-release or build suffix, a field of ten digits or more, or
# whitespace anywhere in the string, a trailing newline included. Whitespace
# is refused although compareSemver trims it: CLAUDE.md allows the plain
# triple only.
#
# The version is read as JSON (jq -c), not raw (jq -r): a raw read inside
# $(...) loses a trailing newline and passes "1.2.3\n", and jq's own regex
# anchors match at a line end. Encoded, a newline stays the two characters \n,
# a number or null carries no quotes, and a manifest of two JSON documents
# reads as two lines, so only one quoted triple matches the whole string below.
#
# CI's manifests job and scripts/version-bump.sh both read a version through
# this script. Usage: bash scripts/plugin-version.sh <path to plugin.json>
set -euo pipefail
export LC_ALL=C

manifest="${1:-}"
if [ -z "$manifest" ]; then
  echo "usage: bash scripts/plugin-version.sh <path to plugin.json>" >&2
  exit 2
fi

raw="$(jq -c '.version' "$manifest" 2>/dev/null)" || exit 1
[[ "$raw" =~ ^\"([0-9]{1,9}\.[0-9]{1,9}\.[0-9]{1,9})\"$ ]] || exit 1
printf '%s\n' "${BASH_REMATCH[1]}"
