#!/usr/bin/env bash
# Runs scripts/platform-compat.sh, from a copy of its own, on a platform
# repository this script plants with a record at each of twelve tags, and
# fails unless what it prints as moved since the previous pin is exactly what
# each pair of records calls for:
#   - records with no outputRevision anywhere (the v0.16.16 shape) print what
#     they printed before outputRevision existed: an inputRevision that moved,
#     with the args it names, and nothing moved for the same record twice;
#   - an outputRevision a tool's previous entry lacked prints as new, one that
#     changed as moved, and one the new entry lacks as gone, and an unchanged
#     one prints nothing;
#   - a tool whose inputRevision and outputRevision both moved prints both,
#     the input first, and a new tool prints only that it is new;
#   - an outputRevision of null reads as none: a value that becomes null
#     prints as gone, and a missing key that becomes null prints nothing;
#   - a retired tool prints only that it is gone, one that held an
#     outputRevision too;
#   - a readOnly that flips prints its old and new value, after the tool's
#     inputRevision line, an unchanged one (false included) prints nothing,
#     and one the new entry lacks reads as none;
#   - a value that moved under contract, plugins or behavior prints its old
#     and new value, and a gateway block (which a record from v0.17.0 on no
#     longer carries) is not compared: one that comes, moves or goes prints
#     nothing.
# Usage (from the repo root): bash scripts/test-platform-compat.sh
set -euo pipefail
# A hook exports GIT_DIR and GIT_INDEX_FILE (as absolute paths in a linked
# worktree), and git honors them over -C, so this script's commits and tags
# would land in the caller's repository. Before the first git call, unset
# every GIT_ variable and read no global or system config; the script this
# one runs inherits both.
for v in "${!GIT_@}"; do unset "$v"; done
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

platform="$tmp/platform"
record="$platform/docs/compat.json"
mkdir -p "$platform/docs"
g() {
  git -C "$platform" -c user.name=test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c tag.gpgsign=false -c core.hooksPath=/dev/null "$@"
}
# tag <tag> <jq filter>: the record at the previous tag, changed by the
# filter, committed and tagged. set(name; f) applies f to one tool's entry.
tag() {
  jq 'def set($name; f): .tools.list |= map(if .name == $name then f else . end); '"$2" \
    "$record" >"$tmp/next.json"
  mv -f "$tmp/next.json" "$record"
  g add -A
  g commit -q -m "$1"
  g tag "$1"
}

g init -q
printf '%s\n' '{"format":1,"contract":{"version":1,"sections":["1"]},"tools":{"count":5,"list":[{"name":"app_status","readOnly":true,"args":["app"],"inputRevision":"b"},{"name":"get_app_logs","readOnly":true,"args":["app"],"inputRevision":"e"},{"name":"get_platform_status","readOnly":true,"args":["version"],"inputRevision":"c"},{"name":"list_apps","readOnly":true,"args":[],"inputRevision":"d"},{"name":"purge_app","readOnly":false,"args":["app"],"inputRevision":"a"}]},"plugins":{"app":{"minVersion":"1.0.0"}}}' \
  >"$record"
tag plain '.'
tag plain-input 'set("purge_app"; .inputRevision = "a2") | set("list_apps"; .args = ["owner"] | .inputRevision = "d2")'
tag typed 'set("app_status"; .outputRevision = "o1") | set("get_app_logs"; .outputRevision = "g1") | set("get_platform_status"; .outputRevision = "p1") | set("list_apps"; .outputRevision = "l1") | set("purge_app"; .inputRevision = "a3")'
tag retyped 'set("app_status"; .outputRevision = "o2") | set("get_app_logs"; .inputRevision = "e2" | .outputRevision = "g2") | set("list_apps"; del(.outputRevision)) | .tools.list += [{"name":"check_name","readOnly":true,"args":["app"],"inputRevision":"f","outputRevision":"n1"}] | .tools.count += 1'
tag nulled 'set("get_platform_status"; .outputRevision = null) | set("purge_app"; .outputRevision = null)'
tag retired '.tools.list |= map(select(.name != "app_status" and .name != "list_apps")) | .tools.count -= 2'
tag flipped 'set("purge_app"; .readOnly = true) | set("get_app_logs"; .readOnly = false | .inputRevision = "e3")'
tag unflagged 'set("get_app_logs"; del(.readOnly))'
tag behaved '.behavior = {"membershipAuthority":"okta"}'
tag gated '.gateway = {"capability":0}'
tag moved-facts '.contract.version = 2 | .plugins.app.minVersion = "1.1.0" | .behavior.membershipAuthority = "platform" | .gateway.capability = 1'
tag ungated 'del(.gateway)'

fail=0
n=0
# expect <what> <previous pin> <pin> [moved line]...: pins the first tag, then
# the second, in a directory of their own, and compares what the second run
# prints, all but its last line (the files it wrote), with the lines given.
expect() {
  local what="$1" from="$2" to="$3" dir out want rc=0
  shift 3
  n=$((n + 1))
  dir="$tmp/case$n/scripts"
  mkdir -p "$dir"
  cp "$here/platform-compat.sh" "$dir/"
  bash "$dir/platform-compat.sh" "$platform" "$from" >/dev/null
  out="$(bash "$dir/platform-compat.sh" "$platform" "$to" 2>&1)" || rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "test-platform-compat: $what exited $rc, expected 0: $out" >&2
    fail=1
    return
  fi
  out="${out%$'\n'*}"
  if [ $# -eq 0 ]; then
    want="platform-compat: nothing moved since the previous pin, $from (commit $(g rev-parse "$from"))"
  else
    want="$(printf 'platform-compat: moved since the previous pin, %s (commit %s) (the resync'"'"'s to-do list):\n' "$from" "$(g rev-parse "$from")"; printf '%s\n' "$@")"
  fi
  if [ "$out" != "$want" ]; then
    printf 'test-platform-compat: %s printed\n%s\nexpected\n%s\n' "$what" "$out" "$want" >&2
    fail=1
  fi
}

expect "the same record twice, with no outputRevision" plain plain
expect "records with no outputRevision" plain plain-input \
  "  tool list_apps: inputRevision moved (args were: none; now: owner)" \
  "  tool purge_app: inputRevision moved (same args: app)"
expect "a record whose tools gain an outputRevision" plain-input typed \
  "  tool app_status: outputRevision new (it now declares an output schema)" \
  "  tool get_app_logs: outputRevision new (it now declares an output schema)" \
  "  tool get_platform_status: outputRevision new (it now declares an output schema)" \
  "  tool list_apps: outputRevision new (it now declares an output schema)" \
  "  tool purge_app: inputRevision moved (same args: app)"
expect "a record whose outputRevisions move, stay and go" typed retyped \
  "  tool app_status: outputRevision moved (its output schema changed)" \
  "  tool check_name: new (args: app)" \
  "  tool get_app_logs: inputRevision moved (same args: app)" \
  "  tool get_app_logs: outputRevision moved (its output schema changed)" \
  "  tool list_apps: outputRevision gone (it no longer declares an output schema)"
expect "the same record twice, with outputRevisions" retyped retyped
expect "a record whose outputRevisions become null" retyped nulled \
  "  tool get_platform_status: outputRevision gone (it no longer declares an output schema)"
expect "a record that retires two tools, one with an outputRevision" nulled retired \
  "  tool app_status: gone" \
  "  tool list_apps: gone"
expect "a record whose tools flip readOnly, one with its inputRevision" retired flipped \
  "  tool get_app_logs: inputRevision moved (same args: app)" \
  "  tool get_app_logs: readOnly was true; now false" \
  "  tool purge_app: readOnly was false; now true"
expect "the same record twice, with a readOnly that is false" flipped flipped
expect "a record whose false readOnly goes" flipped unflagged \
  "  tool get_app_logs: readOnly was false; now none"
expect "a record that gains a gateway block" behaved gated
expect "a record whose contract, plugin floor and behavior move, beside a gateway block that moves" gated moved-facts \
  '  behavior.membershipAuthority: was "okta"; now "platform"' \
  "  contract.version: was 1; now 2" \
  '  plugins.app.minVersion: was "1.0.0"; now "1.1.0"'
expect "a record whose gateway block goes" moved-facts ungated

[ "$fail" -eq 0 ] || exit 1
echo "test-platform-compat: OK ($n cases: a record with no outputRevision reads as before; an outputRevision that comes, moves or goes is listed, an unchanged one is not, and a null one reads as none; a retired tool prints only that it is gone; a readOnly that flips or goes is listed, an unchanged one is not; a contract, plugin floor or behavior value that moves is listed, and a gateway block is never compared)"
