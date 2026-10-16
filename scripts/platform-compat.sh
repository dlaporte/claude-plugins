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
#   bash scripts/platform-compat.sh <platform checkout> <ref>   (a release tag, e.g. v0.16.16)
# It refuses a ref with no docs/compat.json (any release before v0.16.16) and
# a record in a format it does not read. When a previous pin exists, it first
# prints what moved since then: each served document whose hash changed, each
# tool whose inputRevision (its input schema) changed, or that came or went,
# each tool whose outputRevision (its output schema, which only some tools
# declare) came, changed or went, and each value under contract, gateway,
# plugins and behavior that changed (the contract's version and sections, the
# gateway capabilities, the plugin floors, the platform behaviors). That list
# is the resync's to-do list.
set -euo pipefail

if ! command -v jq >/dev/null; then
  echo "platform-compat: jq is required" >&2
  exit 2
fi

platform="${1:-}"
ref="${2:-}"
if [ -z "$platform" ] || [ ! -d "$platform" ] || [ -z "$ref" ]; then
  echo "usage: bash scripts/platform-compat.sh <platform checkout> <ref>" >&2
  exit 2
fi

here="$(cd "$(dirname "$0")" && pwd)"
out="$here/platform-compat.json"
list="$here/platform-tools.txt"
source_file="docs/compat.json"

if ! commit="$(git -C "$platform" rev-parse --verify --quiet --end-of-options "$ref^{commit}")"; then
  echo "platform-compat: $ref is not a commit in $platform" >&2
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

# What moved since the previous pin, read before it is overwritten.
if [ ! -e "$out" ]; then
  echo "platform-compat: no previous pin (${out#"$PWD"/} did not exist), so there is nothing to compare"
elif ! moved="$(jq -r -n --slurpfile old "$out" --slurpfile new "$tmp/pinned.json" '
  def by_name: [(.tools.list // [])[] | {key: .name, value: .}] | from_entries;
  def args: (.args // []) | if length == 0 then "none" else join(", ") end;
  # Every key either side holds, once, sorted.
  def all_keys($a; $b): [$a, $b] | map(keys) | add | unique | .[];
  # Each leaf under an object as {key: "a.b.c", value: its JSON}; a list is
  # one leaf.
  def leaves($path): if type == "object" and length > 0
    then to_entries[] as $e | $e.value | leaves($path + [$e.key])
    else {key: ($path | join(".")), value: tojson} end;
  def facts: [{contract, gateway, plugins, behavior} | leaves([])] | from_entries;
  $old[0] as $o | $new[0] as $n
  | ($o.served // {}) as $os | ($n.served // {}) as $ns
  | ($o | by_name) as $ot | ($n | by_name) as $nt
  | ($o | facts) as $of | ($n | facts) as $nf
  | (all_keys($os; $ns) as $k
     | if ($os | has($k) | not) then "  served \($k): new"
       elif ($ns | has($k) | not) then "  served \($k): gone"
       elif $os[$k] != $ns[$k] then "  served \($k): hash moved"
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
              else "  tool \($k): outputRevision moved (its output schema changed)" end)
       end),
    (all_keys($of; $nf) as $k
     | if ($of | has($k) | not) then "  \($k): new (\($nf[$k]))"
       elif ($nf | has($k) | not) then "  \($k): gone (was \($of[$k]))"
       elif $of[$k] != $nf[$k] then "  \($k): was \($of[$k]); now \($nf[$k])"
       else empty end)
')"; then
  echo "platform-compat: the previous ${out#"$PWD"/} could not be read, so nothing was compared; compare with git diff after this run instead" >&2
else
  previous="$(jq -r '"\(.pinned.ref // "an unknown ref") (commit \(.pinned.commit // "unknown"))"' "$out" 2>/dev/null || echo "an unreadable pin")"
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
  echo "# Generated by scripts/platform-compat.sh; do not edit by hand. Refresh at each"
  echo "# resync with: bash scripts/platform-compat.sh <platform checkout> <release tag>"
  cat "$tmp/names"
} >"$tmp/list"
mv -f "$tmp/list" "$list"
echo "platform-compat: pinned $ref (commit $commit): wrote ${out#"$PWD"/} and ${list#"$PWD"/}, $count tools, contract $(jq -r '.contract.version' "$out"), app plugin floor $(jq -r '.plugins.app.minVersion' "$out")"
