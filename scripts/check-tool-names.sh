#!/usr/bin/env bash
# Fails if the innovation-platform plugin names an MCP tool the platform does
# not serve (a misspelling, or a tool the platform has retired), or if it
# never names a tool the platform does serve (a new tool no skill covers yet,
# the reverse direction of the 2026-10-12 review's D06). The platform's tool
# names are pinned in scripts/platform-tools.txt (refreshed at each resync by
# scripts/platform-tools.sh), so this needs no platform checkout.
#
# Usage: bash scripts/check-tool-names.sh [--list] [--partial] [path]   (default plugins/innovation-platform)
#   --list     also prints every tool name the plugin uses, the allowlisted
#              names it met, and the pinned tools it never names.
#   --partial  skips the reverse check, for a tree that is not the whole
#              plugin (the fixture scripts/test-check-tool-names.sh runs).
#
# A pinned tool counts as named when any checked span below names it: a
# snake_case name in backticks, a name on a front-matter description: line,
# or a call in a fenced code block.
#
# What counts as a tool name. In the plugin's Markdown, a snake_case name in
# backticks is checked when either:
#   - it is called like a tool: "call `x`" (the word call, calls, called or
#     calling, not "recall"), "`x` tool", "`x` MCP tool", "`x(...)`",
#     "`x {...}`" or "`x arg=...`"; or
#   - it is named like one: its first word is a verb a pinned tool begins with
#     (get_, list_, set_, grant_ and the rest, read from the pinned list). The
#     one tool named noun first, app_status, does not make app_ a verb, since
#     app_ also begins many refusal codes.
# Every snake_case word on a skill's front-matter description: line is checked
# the second way, slash-joined lists (a/b/c) included. Inside a fenced code
# block, a line that begins with a snake_case name followed by ( or { is a
# call, and is checked the first way; a shell function definition, name() {,
# is not. A checked name passes if it is pinned, or listed in
# scripts/tool-name-allowlist.txt (arguments, refusal codes, fields and
# app-code functions that happen to begin with a tool verb).
#
# Anything else, such as an argument, a field, a settings key or a refusal
# code, is not checked. So a misspelling that is neither called like a tool
# nor begins with a tool verb (`app_statsu` on its own) is not caught.
# scripts/test-check-tool-names.sh holds a fixture for each of these rules.
set -euo pipefail

list=0
partial=0
while [ $# -gt 0 ]; do
  case "$1" in
    --list) list=1; shift ;;
    --partial) partial=1; shift ;;
    *) break ;;
  esac
done
target="${1:-plugins/innovation-platform}"
here="$(cd "$(dirname "$0")" && pwd)"
pinned_file="$here/platform-tools.txt"
allow_file="$here/tool-name-allowlist.txt"

if [ ! -d "$target" ]; then
  echo "check-tool-names: no such directory: $target" >&2
  exit 2
fi
for f in "$pinned_file" "$allow_file"; do
  if [ ! -r "$f" ]; then
    echo "check-tool-names: cannot read $f" >&2
    exit 2
  fi
done

# grep exits 1 for "no match", which is not an error here; 2 is.
grep_or_none() {
  local rc=0
  grep "$@" || rc=$?
  [ "$rc" -le 1 ] || { echo "check-tool-names: grep failed ($rc)" >&2; exit 2; }
}

spans="$(grep_or_none -rnoE --include='*.md' \
  '((^|[^A-Za-z])[Cc]all(s|ed|ing)? )?`[a-z][a-z0-9]*(_[a-z0-9]+)+(`( (MCP )?tools?)?|[(]| [{]| [a-z_]+=)' \
  -- "$target")"
descriptions="$(grep_or_none -rnE --include='SKILL.md' '^description:' -- "$target")"
# Calls inside fenced code blocks: <file>:<line>:<name>, one per call.
fenced="$(find "$target" -type f -name '*.md' -exec awk '
  FNR == 1 { fence = 0 }
  /^[[:space:]]*(```|~~~)/ { fence = !fence; next }
  fence && /^[[:space:]]*[a-z][a-z0-9]*(_[a-z0-9]+)+[[:space:]]*[({]/ {
    s = $0; sub(/^[[:space:]]*/, "", s)
    match(s, /^[a-z][a-z0-9]*(_[a-z0-9]+)+/)
    name = substr(s, 1, RLENGTH)
    if (substr(s, RLENGTH + 1) ~ /^[[:space:]]*[(][[:space:]]*[)][[:space:]]*[{]/) next
    print FILENAME ":" FNR ":" name
  }
' {} +)"

# The awk program reads the pinned list, then the allowlist, then the hits,
# with a marker line between them.
awk -v list="$list" -v partial="$partial" -v target="$target" '
  function strip(s) { sub(/#.*/, "", s); gsub(/[[:space:]]+/, "", s); return s }
  section == 0 {
    if ($0 == "\034") { section = 1; next }
    n = strip($0); if (n == "") next
    pinned[n] = 1; npinned++
    v = n; sub(/_.*/, "", v)
    if (n != "app_status") verb[v] = 1
    next
  }
  section == 1 {
    if ($0 == "\034") { section = 2; next }
    n = strip($0); if (n == "") next
    if (n in pinned) { printf "check-tool-names: %s is in the allowlist but is a pinned tool; remove it from %s\n", n, "scripts/tool-name-allowlist.txt" > "/dev/stderr"; bad = 1 }
    allow[n] = 1
    next
  }
  # Judges one name met at where (file:line); cue is 1 when it was called
  # like a tool.
  function judge(where, name, cue,    v) {
    if (name in pinned) { used[name] = 1; return }
    if (name in allow) { allowed[name] = 1; return }
    v = name; sub(/_.*/, "", v)
    if (v in verb) { printf "%s: `%s` is named like a tool but is not one the platform serves\n", where, name; hits++; return }
    if (cue) { printf "%s: `%s` is called like a tool but is not one the platform serves\n", where, name; hits++; return }
  }
  # Splits <file>:<line>:<rest> into where and rest.
  function locate(rec,    i, file) {
    i = index(rec, ":"); file = substr(rec, 1, i - 1); rec = substr(rec, i + 1)
    i = index(rec, ":"); where = file ":" substr(rec, 1, i - 1)
    return substr(rec, i + 1)
  }
  section == 2 && /^S/ {
    # S<file>:<line>:<span>; a span that does not open with its backtick
    # opens with the word call.
    m = locate(substr($0, 2))
    cue = 0
    if (substr(m, 1, 1) != "`") { cue = 1; sub(/^[^`]*/, "", m) }
    m = substr(m, 2)
    match(m, /^[a-z][a-z0-9]*(_[a-z0-9]+)+/)
    name = substr(m, 1, RLENGTH); rest = substr(m, RLENGTH + 1)
    if (rest !~ /^`/ || rest ~ /tools?$/) cue = 1
    judge(where, name, cue)
    next
  }
  section == 2 && /^F/ {
    # F<file>:<line>:<name>, a call in a fenced code block
    name = locate(substr($0, 2))
    judge(where, name, 1)
    next
  }
  section == 2 && /^D/ {
    # D<file>:<line>:description: ...
    m = locate(substr($0, 2))
    while (match(m, /[a-z][a-z0-9]*(_[a-z0-9]+)+/)) {
      w = substr(m, RSTART, RLENGTH)
      before = (RSTART > 1) ? substr(m, RSTART - 1, 1) : " "
      after = substr(m, RSTART + RLENGTH, 1)
      m = substr(m, RSTART + RLENGTH)
      if (before ~ /[A-Za-z0-9_.-]/ || after ~ /[A-Za-z0-9_-]/) continue
      judge(where, w, 0)
    }
    next
  }
  END {
    if (npinned == 0) { print "check-tool-names: the pinned list is empty" > "/dev/stderr"; exit 2 }
    if (list) {
      nu = 0; for (n in used) nu++
      printf "Tool names the plugin uses (%d of %d pinned):\n", nu, npinned
      fflush(); for (n in used) print "  " n | "LC_ALL=C sort"; close("LC_ALL=C sort")
      print "Allowlisted names it met:"
      fflush(); for (n in allowed) print "  " n | "LC_ALL=C sort"; close("LC_ALL=C sort")
      print "Pinned tools it never names:"
      fflush(); for (n in pinned) if (!(n in used)) print "  " n | "LC_ALL=C sort"; close("LC_ALL=C sort")
    }
    if (bad) exit 2
    # The reverse check: every pinned tool is named somewhere in the plugin.
    # One line per tool, sorted, with no backticks, so a line here never
    # reads as a planted name to scripts/test-check-tool-names.sh.
    unnamed = 0
    if (!partial) {
      fflush()
      for (n in pinned) if (!(n in used)) {
        printf "%s: pinned tool %s is never named\n", target, n | "LC_ALL=C sort"
        unnamed++
      }
      close("LC_ALL=C sort")
    }
    if (hits) {
      fflush()
      printf "check-tool-names: FAIL, %d name(s) above are not in scripts/platform-tools.txt. Fix the name, or if it is not a tool (a refusal code, a field), add it to scripts/tool-name-allowlist.txt.\n", hits > "/dev/stderr"
    }
    if (unnamed) {
      printf "check-tool-names: FAIL, %d pinned tool(s) above are never named in %s. Name each where a skill uses it, or, if the platform no longer serves it, refresh scripts/platform-tools.txt with scripts/platform-tools.sh.\n", unnamed, target > "/dev/stderr"
    }
    if (hits || unnamed) exit 1
    printf "check-tool-names: OK (%s, %d pinned tools, all named)\n", target, npinned
  }
' <(
  cat "$pinned_file"; printf '\034\n'
  cat "$allow_file"; printf '\034\n'
  if [ -n "$spans" ]; then printf '%s\n' "$spans" | sed 's/^/S/'; fi
  if [ -n "$descriptions" ]; then printf '%s\n' "$descriptions" | sed 's/^/D/'; fi
  if [ -n "$fenced" ]; then printf '%s\n' "$fenced" | sed 's/^/F/'; fi
)
