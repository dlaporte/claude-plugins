#!/usr/bin/env bash
# CI's version-gate-parity job: every innovation-platform skill holds the
# Version gate block, once, byte for byte as its one source,
# scripts/version-gate.md, has it. scripts/render-gates.sh writes the blocks
# from that source, and its --check runs this script.
#
# A block runs from a line that begins "## Version gate" to the first line
# after it that reads "Carry on." exactly. Each skill must hold one heading,
# one such line after it and none elsewhere; the source must be that block
# alone. Each skill is checked on its own, so a malformed edit made the same
# way in every skill fails too (a comparison of the copies with each other
# would pass it).
#
# Usage (from the repo root): bash scripts/check-version-gate.sh [skills dir] [source]
#   (default plugins/innovation-platform/skills and scripts/version-gate.md)
# Prints a ::error line (a GitHub annotation) for each problem. Exits 0 when
# every skill holds the source's block, 1 when a block differs from it (the
# first differing line is named), and 2 when a block or the source is
# malformed, or there is no skill to read; scripts/render-gates.sh writes
# nothing on 2, since it cannot locate every block.
# scripts/test-check-version-gate.sh runs this on skills it plants.
set -euo pipefail
export LC_ALL=C
here="$(cd "$(dirname "$0")" && pwd)"

skills="${1:-plugins/innovation-platform/skills}"
source_file="${2:-$here/version-gate.md}"
source_name="${source_file#"$PWD"/}"

# Reads one file (and, for a skill, the source from srcfile). Prints one
# problem a line, "<line>\t<message>" (line 0 for the whole file), and exits
# 2 for a malformed block, 1 for a block that differs from the source, 0
# otherwise. whole=1 checks the source itself: the block alone.
prog='
  BEGIN { if (srcfile != "") while ((getline l < srcfile) > 0) src[++ns] = l }
  { text[FNR] = $0 }
  /^## Version gate/ { h[++nh] = FNR }
  $0 == "Carry on." { t[++nt] = FNR }
  END {
    if (nh == 0) { print "0\tno \"## Version gate\" heading, so no gate block"; exit 2 }
    bad = 0
    for (i = 2; i <= nh; i++) { print h[i] "\ta second \"## Version gate\" heading: a file holds one gate block"; bad = 1 }
    e = 0
    for (i = 1; i <= nt; i++) if (t[i] > h[1]) { e = t[i]; break }
    if (e == 0) { print h[1] "\tthe gate block that starts here has no \"Carry on.\" line to end it"; bad = 1 }
    for (i = 1; i <= nt; i++) if (t[i] != e) { print t[i] "\ta \"Carry on.\" line outside the gate block: only its last line reads so"; bad = 1 }
    if (bad) exit 2
    if (whole) {
      if (h[1] != 1) { print "1\ta line before the heading: the source is the gate block alone"; bad = 1 }
      if (e != FNR) { print e + 1 "\ta line after \"Carry on.\": the source is the gate block alone"; bad = 1 }
      exit bad ? 2 : 0
    }
    n = e - h[1] + 1
    for (i = 1; i <= n || i <= ns; i++) {
      if (i > n || i > ns || text[h[1] + i - 1] != src[i]) {
        print (i > n ? e : h[1] + i - 1) "\tthe gate block differs from " srcname " here (its line " i ")"
        exit 1
      }
    }
  }
'
# annotate <file> <awk output>: the problems as GitHub annotations.
annotate() {
  local line msg
  [ -n "$2" ] || return 0
  while IFS=$'\t' read -r line msg; do
    if [ "$line" = 0 ]; then
      echo "::error file=$1::$msg"
    else
      echo "::error file=$1,line=$line::$msg"
    fi
  done <<<"$2"
}

if [ ! -f "$source_file" ] || [ ! -r "$source_file" ]; then
  echo "check-version-gate: cannot read $source_name" >&2
  exit 2
fi
rc=0
out="$(awk -v whole=1 "$prog" "$source_file")" || rc=$?
if [ "$rc" -ne 0 ]; then
  annotate "$source_name" "$out"
  echo "check-version-gate: FAIL, $source_name is not one gate block alone, from its \"## Version gate\" heading to its \"Carry on.\" line." >&2
  exit 2
fi

worst=0
count=0
for f in "$skills"/*/SKILL.md; do
  [ -e "$f" ] || continue
  count=$((count + 1))
  rc=0
  out="$(awk -v srcfile="$source_file" -v srcname="$source_name" "$prog" "$f")" || rc=$?
  annotate "$f" "$out"
  if [ "$rc" -gt "$worst" ]; then worst="$rc"; fi
done
if [ "$count" -eq 0 ]; then
  echo "check-version-gate: no skills under $skills" >&2
  exit 2
fi
if [ "$worst" -eq 2 ]; then
  echo "check-version-gate: FAIL, a skill's gate block above cannot be read: each skill holds one, from its \"## Version gate\" heading to its \"Carry on.\" line. Restore the heading or the line, then run bash scripts/render-gates.sh." >&2
  exit 2
fi
if [ "$worst" -eq 1 ]; then
  echo "check-version-gate: FAIL, a skill's Version gate above differs from $source_name, its one source. Edit that file, never a skill's copy, and run bash scripts/render-gates.sh." >&2
  exit 1
fi
echo "check-version-gate: OK ($count skills each hold $source_name's block, once)"
