#!/usr/bin/env bash
# Writes the Version gate into every innovation-platform skill from its one
# source, scripts/version-gate.md: in each plugins/innovation-platform/
# skills/*/SKILL.md, the lines from the "## Version gate" heading through the
# "Carry on." line become the source's lines, byte for byte, and nothing else
# in the file moves. Every skill keeps the whole gate, so the gate runs when a
# skill is invoked alone; the copies are written here, never edited by hand.
# To change the gate, edit scripts/version-gate.md and run this.
#
# scripts/check-version-gate.sh locates every block first (it is the one home
# for what a block is), and nothing is written when it cannot: a block with
# no heading, no "Carry on." line or two of either, or a source that is not
# one block alone (that check's exit 2). Restore such a block by hand, then
# run this again.
#
# Usage (from the repo root): bash scripts/render-gates.sh [--check] [skills dir] [source]
#   (default plugins/innovation-platform/skills and scripts/version-gate.md)
#   --check  writes nothing: runs scripts/check-version-gate.sh, which fails
#            when a skill's block differs from the source (exit 1) or is
#            malformed (exit 2). CI's version-gate-parity job runs it.
# Prints each skill it rewrote and an OK line. scripts/test-render-gates.sh
# runs this on skills it plants.
set -euo pipefail
export LC_ALL=C
here="$(cd "$(dirname "$0")" && pwd)"

if [ "${1:-}" = --check ]; then
  shift
  exec bash "$here/check-version-gate.sh" "$@"
fi
skills="${1:-plugins/innovation-platform/skills}"
source_file="${2:-$here/version-gate.md}"
source_name="${source_file#"$PWD"/}"

rc=0
out="$(bash "$here/check-version-gate.sh" "$skills" "$source_file" 2>&1)" || rc=$?
if [ "$rc" -gt 1 ]; then
  printf '%s\n' "$out" >&2
  echo "render-gates: wrote nothing: the check above cannot locate every gate block." >&2
  exit 2
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
count=0
changed=0
for f in "$skills"/*/SKILL.md; do
  count=$((count + 1))
  awk -v srcfile="$source_file" '
    BEGIN { while ((getline l < srcfile) > 0) src[++ns] = l }
    !done && /^## Version gate/ { for (i = 1; i <= ns; i++) print src[i]; skip = 1; done = 1; next }
    skip { if ($0 == "Carry on.") skip = 0; next }
    { print }
  ' "$f" >"$tmp"
  if ! cmp -s "$tmp" "$f"; then
    # Written through, so the file keeps its mode.
    cat "$tmp" >"$f"
    changed=$((changed + 1))
    echo "render-gates: wrote $f"
  fi
done
echo "render-gates: OK ($count skills hold $source_name's block; $changed rewritten)"
