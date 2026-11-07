#!/usr/bin/env bash
# Fails if scripts/platform-tools.txt is not the tool list of the pinned
# record, scripts/platform-compat.json. One run of scripts/platform-compat.sh
# writes both, so they disagree only when one was edited by hand or only one
# was regenerated. The list's first two lines must be the header that run
# writes, naming the record's tool count, pinned ref and pinned commit, and
# its other lines must be exactly the record's tools.list names, in byte
# order. The record must also be pinned at a release tag: its pinned.ref of
# the form v and a plain MAJOR.MINOR.PATCH triple (scripts/semver.sh's
# semver_release_tag), the only form platform-compat.sh pins. A branch or a
# commit can still move before the release, and a preview
# (platform-compat.sh --preview) is never the committed pin; CI cannot ask the
# platform repository, so the ref's form is what it checks.
# scripts/test-check-platform-tools.sh runs this on files it plants, the
# passing pair written by platform-compat.sh itself.
#
# Usage: bash scripts/check-platform-tools.sh [record] [list]
#   (default scripts/platform-compat.json and scripts/platform-tools.txt)
# Prints file:line: and what disagrees, and exits 1 if anything does, or if
# the record is not pinned at a release tag. Exits 2 when the record is not a
# format 1 record with a pinned ref and commit and a list of tool names, or
# the list cannot be read.
set -euo pipefail
export LC_ALL=C

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$here/lib.sh"
# shellcheck source=scripts/semver.sh
. "$here/semver.sh"
require_jq

record="${1:-$here/platform-compat.json}"
list="${2:-$here/platform-tools.txt}"
record_name="${record#"$PWD"/}"
list_name="${list#"$PWD"/}"

if ! jq -e '.format == 1
    and (.pinned.ref | type == "string" and length > 0)
    and (.pinned.commit | type == "string" and test("^[0-9a-f]{40}$"))
    and (.tools.list | type == "array" and length > 0 and all(.[]; .name | type == "string"))' \
    "$record" >/dev/null 2>&1; then
  echo "check-platform-tools: $record_name is not a format 1 record with a pinned ref and commit and a list of tool names; regenerate it with scripts/platform-compat.sh" >&2
  exit 2
fi
if [ ! -f "$list" ] || [ ! -r "$list" ]; then
  echo "check-platform-tools: cannot read $list_name" >&2
  exit 2
fi

ref="$(jq -r '.pinned.ref' "$record")"
commit="$(jq -r '.pinned.commit' "$record")"
count="$(jq '.tools.list | length' "$record")"
if ! semver_release_tag "$ref"; then
  echo "check-platform-tools: FAIL, $record_name is pinned at $ref, which is not a release tag (v and a plain MAJOR.MINOR.PATCH triple). Pin a release with scripts/platform-compat.sh <platform checkout> <release tag>; a check before a release runs with --preview, whose files are never committed." >&2
  exit 1
fi

fail=0
# The header as scripts/platform-compat.sh writes it, compared whole, so a ref
# that only begins or ends the same way does not pass.
if [ "$(sed -n 1p "$list")" != "# The platform's MCP tool names, one per line: $count tools at $ref" ]; then
  echo "$list_name:1: the header does not name the record's $count tools at its pinned ref, $ref"
  fail=1
fi
if [ "$(sed -n 2p "$list")" != "# (commit $commit), from tools.list of docs/compat.json." ]; then
  echo "$list_name:2: the header does not name the record's pinned commit, $commit"
  fail=1
fi
if ! diff <(grep -v '^#' "$list") <(jq -r '.tools.list[].name' "$record" | sort); then
  echo "$list_name: its names are not the names in tools.list of $record_name, in byte order (diff above: < the list, > the record)"
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo "check-platform-tools: FAIL, $list_name is not the tool list of $record_name, pinned at $ref. Regenerate both with scripts/platform-compat.sh; never edit either by hand." >&2
  exit 1
fi
echo "check-platform-tools: OK (the $count pinned tool names are the record's, at $ref)"
