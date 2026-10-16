#!/usr/bin/env bash
# Runs scripts/check-platform-tools.sh on records and lists this script plants
# in a temporary directory, and fails unless each exits as it should:
#   - the pair scripts/platform-compat.sh writes, from a planted platform
#     repository tagged v0.16.16, passes, so the generator's header and the
#     check's agree;
#   - each disagreement fails (exit 1): a name gone from the list, a name the
#     record lacks, the names out of byte order, and a header naming another
#     commit, another count, another ref, a ref that only begins the same way,
#     or one whose dots are other characters (the compare is not a pattern);
#   - a record with no pinned key, no pinned ref, a short pinned commit,
#     another format or no JSON at all, and a missing list, cannot be read
#     (exit 2).
# Usage (from the repo root): bash scripts/test-check-platform-tools.sh
set -euo pipefail
# A hook exports GIT_DIR and GIT_INDEX_FILE (as absolute paths in a linked
# worktree), and git honors them over -C, so this script's commit and its
# v0.16.16 tag would land in the caller's repository. Before the first git
# call, unset every GIT_ variable and read no global or system config; the
# scripts this one runs inherit both.
for v in "${!GIT_@}"; do unset "$v"; done
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

here="$(cd "$(dirname "$0")" && pwd)"
check="$here/check-platform-tools.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# The passing pair: platform-compat.sh, run from a copy of its own, pins a
# three-tool record (listed out of byte order) at a planted tag.
platform="$tmp/platform"
mkdir -p "$platform/docs" "$tmp/scripts"
printf '%s\n' '{"format":1,"contract":{"version":1,"sections":["1"]},"tools":{"count":3,"list":[{"name":"purge_app","args":["app"],"inputRevision":"a"},{"name":"app_status","args":["app"],"inputRevision":"b"},{"name":"get_app_logs","args":["app"],"inputRevision":"c"}]},"plugins":{"app":{"minVersion":"1.0.0"}}}' \
  >"$platform/docs/compat.json"
g() {
  git -C "$platform" -c user.name=test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c tag.gpgsign=false -c core.hooksPath=/dev/null "$@"
}
g init -q
g add -A
g commit -q -m record
g tag v0.16.16
cp "$here/platform-compat.sh" "$tmp/scripts/"
bash "$tmp/scripts/platform-compat.sh" "$platform" v0.16.16 >/dev/null
record="$tmp/scripts/platform-compat.json"
list="$tmp/scripts/platform-tools.txt"

fail=0
n=0
# expect <what> <expected exit> <record> <list>
expect() {
  local rc=0 out
  n=$((n + 1))
  out="$(bash "$check" "$3" "$4" 2>&1)" || rc=$?
  if [ "$rc" -ne "$2" ]; then
    echo "test-check-platform-tools: $1 exited $rc, expected $2: $out" >&2
    fail=1
  fi
}

expect "the pair platform-compat.sh writes" 0 "$record" "$list"

grep -v '^purge_app$' "$list" >"$tmp/missing.txt"
expect "a name gone from the list" 1 "$record" "$tmp/missing.txt"
{ cat "$list"; echo renew_app; } >"$tmp/extra.txt"
expect "a name the record lacks" 1 "$record" "$tmp/extra.txt"
{ grep '^#' "$list"; grep -v '^#' "$list" | LC_ALL=C sort -r; } >"$tmp/order.txt"
expect "the names out of byte order" 1 "$record" "$tmp/order.txt"
sed 's/(commit [0-9a-f]\{40\})/(commit 464c5f3b0000000000000000000000000000beef)/' "$list" >"$tmp/commit.txt"
expect "a header naming another commit" 1 "$record" "$tmp/commit.txt"
sed '1s/: 3 tools at/: 4 tools at/' "$list" >"$tmp/count.txt"
expect "a header naming another count" 1 "$record" "$tmp/count.txt"
sed '1s/ at v0\.16\.16$/ at v0.16.15/' "$list" >"$tmp/ref.txt"
expect "a header naming another ref" 1 "$record" "$tmp/ref.txt"
sed '1s/ at v0\.16\.16$/ at v0.16.160/' "$list" >"$tmp/longer.txt"
expect "a header naming a ref that only begins the same way" 1 "$record" "$tmp/longer.txt"
sed '1s/ at v0\.16\.16$/ at v0x16x16/' "$list" >"$tmp/dots.txt"
expect "a header naming the ref with its dots changed" 1 "$record" "$tmp/dots.txt"

jq 'del(.pinned)' "$record" >"$tmp/nopin.json"
expect "a record with no pinned key" 2 "$tmp/nopin.json" "$list"
jq 'del(.pinned.ref)' "$record" >"$tmp/noref.json"
expect "a record with a pinned commit but no ref" 2 "$tmp/noref.json" "$list"
jq '.pinned.commit |= .[0:8]' "$record" >"$tmp/short.json"
expect "a record with a short pinned commit" 2 "$tmp/short.json" "$list"
jq '.format = 2' "$record" >"$tmp/format.json"
expect "a record in format 2" 2 "$tmp/format.json" "$list"
echo 'not json' >"$tmp/notjson.json"
expect "a record that is not JSON" 2 "$tmp/notjson.json" "$list"
expect "a missing list" 2 "$record" "$tmp/nosuch.txt"

# A failure names the line and what it should read.
out="$(bash "$check" "$record" "$tmp/dots.txt" 2>/dev/null)" || true
want="$tmp/dots.txt:1: the header does not name the record's 3 tools at its pinned ref, v0.16.16"
if [ "$out" != "$want" ]; then
  echo "test-check-platform-tools: the failure reads \"$out\", expected \"$want\"" >&2
  fail=1
fi

[ "$fail" -eq 0 ] || exit 1
echo "test-check-platform-tools: OK ($n cases: the pair platform-compat.sh writes passes; each planted disagreement fails; an unreadable record or list is refused)"
