#!/usr/bin/env bash
# Pins the platform release this plugin is checked against. Writes
# scripts/platform-compat.json, the platform's compatibility record
# (docs/compat.json, which every release from v0.16.16 generates and commits)
# at a given ref, with "pinned": { "ref", "commit" } added as its last key,
# and scripts/platform-tools.txt, the record's tool names, one per line. CI's
# platform-compat and tool-names jobs check the plugin against those copies,
# so CI never needs the platform repository.
#
# Re-run it at each resync of the plugin with the platform, then commit both
# files with the skill changes they go with:
#   bash scripts/platform-compat.sh <platform checkout> <release tag>   (e.g. v0.16.16)
# A pin is written only at a release tag: a ref of the form v and a plain
# MAJOR.MINOR.PATCH triple (scripts/semver.sh's semver_release_tag), read as
# refs/tags/<ref> in the checkout, annotated or lightweight, and pinned at the
# commit it names. A branch, a raw commit SHA, a tag of another form, and a
# release's name that is not a tag in the checkout (not fetched yet, or a
# branch of that name) are refused, so nothing that can still move becomes
# the committed pin; scripts/check-platform-tools.sh fails a committed pin
# whose ref is not of that form.
#
# To check the plugin against a platform commit before its release (the
# platform's release order does, at the release commit), preview it instead:
#   bash scripts/platform-compat.sh --preview <platform checkout> <ref>
# takes any ref that names a commit, prints what moved since the committed
# pin, and writes the same two files as scripts/platform-compat.preview.json
# and scripts/platform-tools.preview.txt, which git ignores, leaving the
# committed pin byte for byte. The checks that take a record or a list read
# the preview when given its paths (CLAUDE.md says how).
#
# It refuses a ref with no docs/compat.json (any release before v0.16.16) and
# a record in a format it does not read. When a previous pin exists, it first
# prints what moved since then: each served document whose hash changed, each
# shipped file whose hash came, changed or went (from platform v0.18.18, the
# files the platform ships into an app that this repository keeps a copy of:
# ci/build-ui.mjs, which the starter's dev/build-ui.mjs mirrors, and the
# function scaffold's app/identity.ts, which scripts/starter-test/ copies),
# each tool whose inputRevision (its input schema) changed, or that came or
# went, each tool whose outputRevision (its output schema, which only some tools
# declare) came, changed or went, each tool whose readOnly flag changed
# (tools.revision hashes it, so a flip alone moves the platform's
# Compatibility: revision), each tool whose adminOnly flag came, flipped or
# went (from platform v0.17.7 a member's client lists no admin-only tool;
# tools.revision does not hash this flag, so a flip alone leaves the
# Compatibility: revision where it was, and the first pin past v0.17.6
# prints one line per tool as the flag comes), and each value under
# contract, plugins and behavior that changed (the contract's version and
# sections, the plugin floors, the platform behaviors). A record from
# v0.17.0 on has no gateway block, and none is compared. That list is the
# resync's to-do list. A preview compares with the committed pin the same way.
# scripts/test-platform-compat.sh runs this on a platform repository it
# plants, in both modes.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$here/lib.sh"
# shellcheck source=scripts/semver.sh
. "$here/semver.sh"
require_jq

preview=0
if [ "${1:-}" = --preview ]; then
  preview=1
  shift
fi
platform="${1:-}"
ref="${2:-}"
if [ -z "$platform" ] || [ ! -d "$platform" ] || [ -z "$ref" ]; then
  echo "usage: bash scripts/platform-compat.sh <platform checkout> <release tag>" >&2
  echo "       bash scripts/platform-compat.sh --preview <platform checkout> <ref>" >&2
  exit 2
fi

# The committed pin, which a preview compares with and never writes.
pin="$here/platform-compat.json"
if [ "$preview" -eq 1 ]; then
  out="$here/platform-compat.preview.json"
  list="$here/platform-tools.preview.txt"
else
  out="$pin"
  list="$here/platform-tools.txt"
fi
source_file="docs/compat.json"
# The end of both refusals below: the preview command and the two files it
# writes, so whoever runs this at a commit (the platform's release order
# does) lands on the right command.
preview_hint() {
  echo "run bash scripts/platform-compat.sh --preview $platform $1, which writes ${here#"$PWD"/}/platform-compat.preview.json and ${here#"$PWD"/}/platform-tools.preview.txt (git ignores both) and leaves the committed pin alone."
}

if [ "$preview" -eq 1 ]; then
  if ! commit="$(git -C "$platform" rev-parse --verify --quiet --end-of-options "$ref^{commit}")"; then
    echo "platform-compat: $ref is not a commit in $platform" >&2
    exit 2
  fi
elif ! semver_release_tag "$ref"; then
  echo "platform-compat: $ref is not a release tag (v and a plain MAJOR.MINOR.PATCH triple), and only a release is pinned. To check a commit before its release, $(preview_hint "$ref")" >&2
  exit 2
elif ! commit="$(git -C "$platform" rev-parse --verify --quiet "refs/tags/$ref^{commit}")"; then
  echo "platform-compat: $ref is not a tag in $platform. Fetch it first (git -C $platform fetch origin tag $ref); to check a commit before its release, $(preview_hint "<commit>")" >&2
  exit 2
fi
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
if ! git -C "$platform" show "$commit:$source_file" >"$tmp/record.json" 2>/dev/null; then
  echo "platform-compat: $ref has no $source_file, so there is no record to pin (a release before v0.16.16 has none)" >&2
  exit 1
fi

# The fields CI reads, checked before anything is written.
problem="$(jq -r '
  if type != "object" then "it is not a JSON object"
  elif .format != 1 then "its format is \(.format | tojson), and this script reads format 1"
  elif has("pinned") then "it already holds a pinned key"
  elif (.tools.list | type) != "array" then "tools.list is not a list"
  elif (.tools.list | length) == 0 then "tools.list is empty"
  elif any(.tools.list[]; (.name | type) != "string" or (.name | test("^[a-z][a-z0-9]*(_[a-z0-9]+)+$") | not)) then "a tools.list name is not a snake_case string"
  elif (.tools.list | map(.name) | unique | length) != (.tools.list | length) then "a tool name appears twice in tools.list"
  elif .tools.count != (.tools.list | length) then "tools.count is \(.tools.count | tojson) but tools.list holds \(.tools.list | length)"
  elif (.contract.sections | type) != "array" or (.contract.sections | length) == 0 or any(.contract.sections[]; type != "string") then "contract.sections is not a list of ids"
  elif (.plugins.app.minVersion | type) != "string" then "plugins.app.minVersion is not a string"
  else empty end
' "$tmp/record.json" 2>&1)" || problem="jq could not read it ($problem)"
if [ -n "$problem" ]; then
  echo "platform-compat: $source_file at $ref is not a record this script reads: $problem" >&2
  exit 1
fi

jq --arg ref "$ref" --arg commit "$commit" '. + {pinned: {ref: $ref, commit: $commit}}' \
  "$tmp/record.json" >"$tmp/pinned.json"
jq -r '.tools.list[].name' "$tmp/record.json" | LC_ALL=C sort >"$tmp/names"
count="$(grep -c . "$tmp/names")"

# What moved since the previous pin, read before a pin overwrites it.
if [ ! -e "$pin" ]; then
  echo "platform-compat: no previous pin (${pin#"$PWD"/} did not exist), so there is nothing to compare"
elif ! moved="$(jq -r -n --slurpfile old "$pin" --slurpfile new "$tmp/pinned.json" '
  def by_name: [(.tools.list // [])[] | {key: .name, value: .}] | from_entries;
  def args: (.args // []) | if length == 0 then "none" else join(", ") end;
  def flag: if . == null then "none" else tojson end;
  # Every key either side holds, once, sorted.
  def all_keys($a; $b): [$a, $b] | map(keys) | add | unique | .[];
  # Each leaf under an object as {key: "a.b.c", value: its JSON}; a list is
  # one leaf.
  def leaves($path): if type == "object" and length > 0
    then to_entries[] as $e | $e.value | leaves($path + [$e.key])
    else {key: ($path | join(".")), value: tojson} end;
  def facts: [{contract, plugins, behavior} | leaves([])] | from_entries;
  $old[0] as $o | $new[0] as $n
  | ($o.served // {}) as $os | ($n.served // {}) as $ns
  | ($o.shipped // {}) as $oh | ($n.shipped // {}) as $nh
  | ($o | by_name) as $ot | ($n | by_name) as $nt
  | ($o | facts) as $of | ($n | facts) as $nf
  | (all_keys($os; $ns) as $k
     | if ($os | has($k) | not) then "  served \($k): new"
       elif ($ns | has($k) | not) then "  served \($k): gone"
       elif $os[$k] != $ns[$k] then "  served \($k): hash moved"
       else empty end),
    # A record before v0.18.18 has no shipped key, so the first pin past it
    # prints each entry as new.
    (all_keys($oh; $nh) as $k
     | if ($oh | has($k) | not) then "  shipped \($k): new"
       elif ($nh | has($k) | not) then "  shipped \($k): gone"
       elif $oh[$k] != $nh[$k] then "  shipped \($k): hash moved"
       else empty end),
    (all_keys($ot; $nt) as $k
     | if ($ot | has($k) | not) then "  tool \($k): new (args: \($nt[$k] | args))"
       elif ($nt | has($k) | not) then "  tool \($k): gone"
       else $ot[$k] as $a | $nt[$k] as $b
         | (if $a.inputRevision == $b.inputRevision then empty
            elif ($a | args) == ($b | args) then "  tool \($k): inputRevision moved (same args: \($b | args))"
            else "  tool \($k): inputRevision moved (args were: \($a | args); now: \($b | args))" end),
           # Only a tool that declares an output schema has an outputRevision;
           # a null one reads as none.
           (($a.outputRevision // null) as $ao | ($b.outputRevision // null) as $bo
            | if $ao == $bo then empty
              elif $ao == null then "  tool \($k): outputRevision new (it now declares an output schema)"
              elif $bo == null then "  tool \($k): outputRevision gone (it no longer declares an output schema)"
              else "  tool \($k): outputRevision moved (its output schema changed)" end),
           # Read without //, which would take false for missing; a missing
           # key reads as none.
           ($a.readOnly as $ar | $b.readOnly as $br
            | if $ar == $br then empty
              else "  tool \($k): readOnly was \($ar | flag); now \($br | flag)" end),
           # The same rule for adminOnly, which only a record from v0.17.7
           # on carries.
           ($a.adminOnly as $aa | $b.adminOnly as $ba
            | if $aa == $ba then empty
              else "  tool \($k): adminOnly was \($aa | flag); now \($ba | flag)" end)
       end),
    (all_keys($of; $nf) as $k
     | if ($of | has($k) | not) then "  \($k): new (\($nf[$k]))"
       elif ($nf | has($k) | not) then "  \($k): gone (was \($of[$k]))"
       elif $of[$k] != $nf[$k] then "  \($k): was \($of[$k]); now \($nf[$k])"
       else empty end)
')"; then
  echo "platform-compat: the previous ${pin#"$PWD"/} could not be read, so nothing was compared; compare with git diff after this run instead" >&2
else
  previous="$(jq -r '"\(.pinned.ref // "an unknown ref") (commit \(.pinned.commit // "unknown"))"' "$pin" 2>/dev/null || echo "an unreadable pin")"
  if [ -z "$moved" ]; then
    echo "platform-compat: nothing moved since the previous pin, $previous"
  else
    echo "platform-compat: moved since the previous pin, $previous (the resync's to-do list):"
    printf '%s\n' "$moved"
  fi
fi

mv -f "$tmp/pinned.json" "$out"
{
  echo "# The platform's MCP tool names, one per line: $count tools at $ref"
  echo "# (commit $commit), from tools.list of $source_file."
  if [ "$preview" -eq 1 ]; then
    echo "# A preview by scripts/platform-compat.sh --preview, never committed. Pin a"
    echo "# release with: bash scripts/platform-compat.sh <platform checkout> <release tag>"
  else
    echo "# Generated by scripts/platform-compat.sh; do not edit by hand. Refresh at each"
    echo "# resync with: bash scripts/platform-compat.sh <platform checkout> <release tag>"
  fi
  cat "$tmp/names"
} >"$tmp/list"
mv -f "$tmp/list" "$list"
facts="$count tools, contract $(jq -r '.contract.version' "$out"), app plugin floor $(jq -r '.plugins.app.minVersion' "$out")"
if [ "$preview" -eq 1 ]; then
  echo "platform-compat: previewed $ref (commit $commit): wrote ${out#"$PWD"/} and ${list#"$PWD"/}, which git ignores, and left the committed pin alone; $facts"
else
  echo "platform-compat: pinned $ref (commit $commit): wrote ${out#"$PWD"/} and ${list#"$PWD"/}, $facts"
fi
