#!/usr/bin/env bash
# Runs scripts/platform-compat.sh, from a copy of the scripts, on a platform
# repository this script plants with a record at each of eighteen release tags
# (v1.0.1, the first, an annotated tag; the rest lightweight), and fails
# unless what it prints as moved since the previous pin is exactly what each
# pair of records calls for:
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
#   - an adminOnly (platform v0.17.7 on) that comes, flips or goes prints its
#     old and new value as readOnly does, after the tool's readOnly line: a
#     record whose every tool gains it (the first resync past v0.17.6) prints
#     one line per tool, an unchanged one (false included) prints nothing;
#   - a value that moved under contract, plugins or behavior prints its old
#     and new value, and a gateway block (which a record from v0.17.0 on no
#     longer carries) is not compared: one that comes, moves or goes prints
#     nothing;
#   - a served document and a shipped file (platform v0.18.18 on) that come,
#     whose hash moves or that go each print so, by path, the served lines
#     first: a record that gains the shipped key (the first resync past
#     v0.18.17) prints each of its entries as new, and the same record twice
#     prints nothing.
# Then the two modes, each with exactly its output and the files it leaves:
#   - a pin is written only at a release tag: an annotated tag and a
#     lightweight one each pin the commit they name; a branch name, a raw
#     commit SHA and a tag of another form (v1.0.16-rc.1) are refused, and so
#     is a release tag's form that is not a tag in the checkout (a branch
#     named v1.0.99), each writing nothing;
#   - --preview takes any commit: at a raw SHA it prints what moved since the
#     committed pin, writes the two preview files and leaves the committed pin
#     byte for byte; with no committed pin it writes the preview alone.
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
# shellcheck source=scripts/test-lib.sh
. "$here/test-lib.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

platform="$tmp/platform"
record="$platform/docs/compat.json"
mkdir -p "$platform/docs"
g() {
  git -C "$platform" -c user.name=test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c tag.gpgsign=false -c core.hooksPath=/dev/null "$@"
}
# tag <tag> <jq filter> [annotated]: the record at the previous tag, changed
# by the filter, committed and tagged. set(name; f) applies f to one tool's
# entry.
tag() {
  jq 'def set($name; f): .tools.list |= map(if .name == $name then f else . end); '"$2" \
    "$record" >"$tmp/next.json"
  mv -f "$tmp/next.json" "$record"
  g add -A
  g commit -q -m "$1"
  if [ "${3:-}" = annotated ]; then g tag -a -m "$1" "$1"; else g tag "$1"; fi
}

g init -q
printf '%s\n' '{"format":1,"contract":{"version":1,"sections":["1"]},"tools":{"count":5,"list":[{"name":"app_status","readOnly":true,"args":["app"],"inputRevision":"b"},{"name":"get_app_logs","readOnly":true,"args":["app"],"inputRevision":"e"},{"name":"get_platform_status","readOnly":true,"args":["version"],"inputRevision":"c"},{"name":"list_apps","readOnly":true,"args":[],"inputRevision":"d"},{"name":"purge_app","readOnly":false,"args":["app"],"inputRevision":"a"}]},"plugins":{"app":{"minVersion":"1.0.0"}}}' \
  >"$record"
tag v1.0.1 '.' annotated
tag v1.0.2 'set("purge_app"; .inputRevision = "a2") | set("list_apps"; .args = ["owner"] | .inputRevision = "d2")'
tag v1.0.3 'set("app_status"; .outputRevision = "o1") | set("get_app_logs"; .outputRevision = "g1") | set("get_platform_status"; .outputRevision = "p1") | set("list_apps"; .outputRevision = "l1") | set("purge_app"; .inputRevision = "a3")'
tag v1.0.4 'set("app_status"; .outputRevision = "o2") | set("get_app_logs"; .inputRevision = "e2" | .outputRevision = "g2") | set("list_apps"; del(.outputRevision)) | .tools.list += [{"name":"check_name","readOnly":true,"args":["app"],"inputRevision":"f","outputRevision":"n1"}] | .tools.count += 1'
tag v1.0.5 'set("get_platform_status"; .outputRevision = null) | set("purge_app"; .outputRevision = null)'
tag v1.0.6 '.tools.list |= map(select(.name != "app_status" and .name != "list_apps")) | .tools.count -= 2'
tag v1.0.7 'set("purge_app"; .readOnly = true) | set("get_app_logs"; .readOnly = false | .inputRevision = "e3")'
tag v1.0.8 'set("get_app_logs"; del(.readOnly))'
tag v1.0.9 '.behavior = {"membershipAuthority":"okta"}'
tag v1.0.10 '.gateway = {"capability":0}'
tag v1.0.11 '.contract.version = 2 | .plugins.app.minVersion = "1.1.0" | .behavior.membershipAuthority = "platform" | .gateway.capability = 1'
tag v1.0.12 'del(.gateway)'
tag v1.0.13 '.tools.list |= map(.adminOnly = (.name == "purge_app"))'
tag v1.0.14 'set("purge_app"; .adminOnly = false) | set("get_app_logs"; .adminOnly = true | .readOnly = true | .inputRevision = "e4")'
tag v1.0.15 'set("purge_app"; del(.adminOnly))'
tag v1.0.16 '.served = {"docs/A.md":"a1","docs/B.md":"b1"}'
tag v1.0.17 '.shipped = {"ci/build-ui.mjs":"u1","ci/fixtures/identity.ts":"i1"}'
tag v1.0.18 '.served["docs/A.md"] = "a2" | del(.served["docs/B.md"]) | .shipped["ci/build-ui.mjs"] = "u2" | del(.shipped["ci/fixtures/identity.ts"]) | .shipped["app/new.ts"] = "n1"'

# fresh: a new directory holding a copy of the scripts, so each case's pin is
# its own (platform-compat.sh writes beside itself). Prints its scripts/.
fresh() {
  local dir
  dir="$(mktemp -d "$tmp/case.XXXXXX")"
  mkdir "$dir/scripts"
  cp "$here"/*.sh "$dir/scripts/"
  printf '%s\n' "$dir/scripts"
}
# pin_pair <previous pin> <pin>: pins the first tag, then the second, from a
# fresh copy, and prints what the second run printed, all but its last line
# (the files it wrote).
pin_pair() {
  local dir out rc=0
  dir="$(fresh)"
  bash "$dir/platform-compat.sh" "$platform" "$1" >/dev/null
  out="$(bash "$dir/platform-compat.sh" "$platform" "$2" 2>&1)" || rc=$?
  if [ "$rc" -ne 0 ]; then
    printf '%s\n' "$out"
    return "$rc"
  fi
  printf '%s\n' "${out%$'\n'*}"
}
# moved <what> <previous pin> <pin> [moved line]...: the lines given are what
# moved from one pin to the next; none means nothing moved.
moved() {
  local what="$1" from="$2" to="$3" want
  shift 3
  if [ $# -eq 0 ]; then
    want="platform-compat: nothing moved since the previous pin, $from (commit $(g rev-parse "$from^{commit}"))"
  else
    want="$(printf 'platform-compat: moved since the previous pin, %s (commit %s) (the resync'"'"'s to-do list):\n' "$from" "$(g rev-parse "$from^{commit}")"; printf '%s\n' "$@")"
  fi
  expect "$what" 0 "$want" pin_pair "$from" "$to"
}

moved "the same record twice, with no outputRevision" v1.0.1 v1.0.1
moved "records with no outputRevision" v1.0.1 v1.0.2 \
  "  tool list_apps: inputRevision moved (args were: none; now: owner)" \
  "  tool purge_app: inputRevision moved (same args: app)"
moved "a record whose tools gain an outputRevision" v1.0.2 v1.0.3 \
  "  tool app_status: outputRevision new (it now declares an output schema)" \
  "  tool get_app_logs: outputRevision new (it now declares an output schema)" \
  "  tool get_platform_status: outputRevision new (it now declares an output schema)" \
  "  tool list_apps: outputRevision new (it now declares an output schema)" \
  "  tool purge_app: inputRevision moved (same args: app)"
moved "a record whose outputRevisions move, stay and go" v1.0.3 v1.0.4 \
  "  tool app_status: outputRevision moved (its output schema changed)" \
  "  tool check_name: new (args: app)" \
  "  tool get_app_logs: inputRevision moved (same args: app)" \
  "  tool get_app_logs: outputRevision moved (its output schema changed)" \
  "  tool list_apps: outputRevision gone (it no longer declares an output schema)"
moved "the same record twice, with outputRevisions" v1.0.4 v1.0.4
moved "a record whose outputRevisions become null" v1.0.4 v1.0.5 \
  "  tool get_platform_status: outputRevision gone (it no longer declares an output schema)"
moved "a record that retires two tools, one with an outputRevision" v1.0.5 v1.0.6 \
  "  tool app_status: gone" \
  "  tool list_apps: gone"
moved "a record whose tools flip readOnly, one with its inputRevision" v1.0.6 v1.0.7 \
  "  tool get_app_logs: inputRevision moved (same args: app)" \
  "  tool get_app_logs: readOnly was true; now false" \
  "  tool purge_app: readOnly was false; now true"
moved "the same record twice, with a readOnly that is false" v1.0.7 v1.0.7
moved "a record whose false readOnly goes" v1.0.7 v1.0.8 \
  "  tool get_app_logs: readOnly was false; now none"
moved "a record that gains a gateway block" v1.0.9 v1.0.10
moved "a record whose contract, plugin floor and behavior move, beside a gateway block that moves" v1.0.10 v1.0.11 \
  '  behavior.membershipAuthority: was "okta"; now "platform"' \
  "  contract.version: was 1; now 2" \
  '  plugins.app.minVersion: was "1.0.0"; now "1.1.0"'
moved "a record whose gateway block goes" v1.0.11 v1.0.12
moved "a record whose every tool gains adminOnly" v1.0.12 v1.0.13 \
  "  tool check_name: adminOnly was none; now false" \
  "  tool get_app_logs: adminOnly was none; now false" \
  "  tool get_platform_status: adminOnly was none; now false" \
  "  tool purge_app: adminOnly was none; now true"
moved "a record whose tools flip adminOnly, one with its inputRevision and readOnly" v1.0.13 v1.0.14 \
  "  tool get_app_logs: inputRevision moved (same args: app)" \
  "  tool get_app_logs: readOnly was none; now true" \
  "  tool get_app_logs: adminOnly was false; now true" \
  "  tool purge_app: adminOnly was true; now false"
moved "the same record twice, with an adminOnly that is false" v1.0.14 v1.0.14
moved "a record whose false adminOnly goes" v1.0.14 v1.0.15 \
  "  tool purge_app: adminOnly was false; now none"
moved "a record that gains served documents" v1.0.15 v1.0.16 \
  "  served docs/A.md: new" \
  "  served docs/B.md: new"
moved "a record that gains the shipped key" v1.0.16 v1.0.17 \
  "  shipped ci/build-ui.mjs: new" \
  "  shipped ci/fixtures/identity.ts: new"
moved "a record whose served and shipped entries come, move and go" v1.0.17 v1.0.18 \
  "  served docs/A.md: hash moved" \
  "  served docs/B.md: gone" \
  "  shipped app/new.ts: new" \
  "  shipped ci/build-ui.mjs: hash moved" \
  "  shipped ci/fixtures/identity.ts: gone"
moved "the same record twice, with served and shipped entries" v1.0.18 v1.0.18

# The two modes. Beside the release tags: a branch, a branch with a release
# tag's form and no such tag, and a tag of another form.
g branch candidate
g branch v1.0.99
g tag v1.0.16-rc.1
head="$(g rev-parse HEAD)"
c1="$(g rev-parse 'v1.0.1^{commit}')"
c2="$(g rev-parse v1.0.2)"
# left <scripts dir>: the pin and preview files a copy holds.
left() {
  local f out="files:"
  for f in platform-compat.json platform-tools.txt platform-compat.preview.json platform-tools.preview.txt; do
    if [ -e "$1/$f" ]; then out="$out $f"; fi
  done
  printf '%s\n' "$out"
}
# compat <scripts dir> <arg>...: one run of that copy, from its repository
# root (so it names its files scripts/...), then the files it holds.
compat() {
  local dir="$1" rc=0
  shift
  (cd "$dir/.." && bash scripts/platform-compat.sh "$@") 2>&1 || rc=$?
  left "$dir"
  return "$rc"
}
# Both refusals end by naming the preview command and the two files it
# writes, so a reader of either repository lands on the right command.
preview_hint() {
  echo "run bash scripts/platform-compat.sh --preview $platform $1, which writes scripts/platform-compat.preview.json and scripts/platform-tools.preview.txt (git ignores both) and leaves the committed pin alone."
}
not_a_release() {
  echo "platform-compat: $1 is not a release tag (v and a plain MAJOR.MINOR.PATCH triple), and only a release is pinned. To check a commit before its release, $(preview_hint "$1")"
}
first_pin="platform-compat: no previous pin (scripts/platform-compat.json did not exist), so there is nothing to compare"
facts="5 tools, contract 1, app plugin floor 1.0.0"

expect "the planted v1.0.1 is an annotated tag" 0 "tag" g cat-file -t v1.0.1
expect "an annotated release tag pins the commit it names" 0 "$(
  echo "$first_pin"
  echo "platform-compat: pinned v1.0.1 (commit $c1): wrote scripts/platform-compat.json and scripts/platform-tools.txt, $facts"
  echo "files: platform-compat.json platform-tools.txt"
)" compat "$(fresh)" "$platform" v1.0.1
expect "a lightweight release tag pins its commit" 0 "$(
  echo "$first_pin"
  echo "platform-compat: pinned v1.0.2 (commit $c2): wrote scripts/platform-compat.json and scripts/platform-tools.txt, $facts"
  echo "files: platform-compat.json platform-tools.txt"
)" compat "$(fresh)" "$platform" v1.0.2
expect "a branch name is not pinned" 2 "$(not_a_release candidate; echo "files:")" \
  compat "$(fresh)" "$platform" candidate
expect "a raw commit SHA is not pinned" 2 "$(not_a_release "$head"; echo "files:")" \
  compat "$(fresh)" "$platform" "$head"
expect "a tag of another form is not pinned" 2 "$(not_a_release v1.0.16-rc.1; echo "files:")" \
  compat "$(fresh)" "$platform" v1.0.16-rc.1
expect "a release tag's form that is not a tag in the checkout is not pinned" 2 "$(
  echo "platform-compat: v1.0.99 is not a tag in $platform. Fetch it first (git -C $platform fetch origin tag v1.0.99); to check a commit before its release, $(preview_hint "<commit>")"
  echo "files:"
)" compat "$(fresh)" "$platform" v1.0.99
expect "no arguments" 2 "$(
  echo "usage: bash scripts/platform-compat.sh <platform checkout> <release tag>"
  echo "       bash scripts/platform-compat.sh --preview <platform checkout> <ref>"
  echo "files:"
)" compat "$(fresh)"

# preview_at <scripts dir> <ref>: a preview at ref beside a committed pin of
# v1.0.1, then the preview list's header and whether the committed pair moved.
preview_at() {
  local dir="$1" rc=0
  (cd "$dir/.." && bash scripts/platform-compat.sh "$platform" v1.0.1 >/dev/null)
  /bin/cp -f "$dir/platform-compat.json" "$dir/../committed.json"
  /bin/cp -f "$dir/platform-tools.txt" "$dir/../committed.txt"
  compat "$dir" --preview "$platform" "$2" || rc=$?
  sed -n 1,2p "$dir/platform-tools.preview.txt"
  if cmp -s "$dir/platform-compat.json" "$dir/../committed.json" && cmp -s "$dir/platform-tools.txt" "$dir/../committed.txt"; then
    echo "the committed pair is byte for byte as it was"
  else
    echo "the committed pair moved"
  fi
  return "$rc"
}
expect "a preview at a raw SHA lists what moved since the committed pin and leaves it alone" 0 "$(
  echo "platform-compat: moved since the previous pin, v1.0.1 (commit $c1) (the resync's to-do list):"
  echo "  tool list_apps: inputRevision moved (args were: none; now: owner)"
  echo "  tool purge_app: inputRevision moved (same args: app)"
  echo "platform-compat: previewed $c2 (commit $c2): wrote scripts/platform-compat.preview.json and scripts/platform-tools.preview.txt, which git ignores, and left the committed pin alone; $facts"
  echo "files: platform-compat.json platform-tools.txt platform-compat.preview.json platform-tools.preview.txt"
  echo "# The platform's MCP tool names, one per line: 5 tools at $c2"
  echo "# (commit $c2), from tools.list of docs/compat.json."
  echo "the committed pair is byte for byte as it was"
)" preview_at "$(fresh)" "$c2"
expect "a preview with no committed pin writes the preview alone" 0 "$(
  echo "$first_pin"
  echo "platform-compat: previewed candidate (commit $head): wrote scripts/platform-compat.preview.json and scripts/platform-tools.preview.txt, which git ignores, and left the committed pin alone; 4 tools, contract 2, app plugin floor 1.1.0"
  echo "files: platform-compat.preview.json platform-tools.preview.txt"
)" compat "$(fresh)" --preview "$platform" candidate

[ "$fail" -eq 0 ] || exit 1
echo "test-platform-compat: OK ($n cases: a record with no outputRevision reads as before; an outputRevision that comes, moves or goes is listed, an unchanged one is not, and a null one reads as none; a retired tool prints only that it is gone; a readOnly or adminOnly that comes, flips or goes is listed, an unchanged one is not; a contract, plugin floor or behavior value that moves is listed, and a gateway block is never compared; a served document or shipped file that comes, moves or goes is listed by path; only a release tag, annotated or lightweight, is pinned, and a preview takes any commit and leaves the committed pin alone)"
