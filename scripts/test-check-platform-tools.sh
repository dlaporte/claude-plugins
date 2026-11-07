#!/usr/bin/env bash
# Runs scripts/check-platform-tools.sh on records and lists this script plants
# in a temporary directory, and fails unless the check's whole output and exit
# status are exactly what each calls for:
#   - the pair scripts/platform-compat.sh writes, from a planted platform
#     repository tagged v0.16.16, passes, so the generator's header and the
#     check's agree;
#   - each disagreement fails (exit 1): a name gone from the list, a name the
#     record lacks, the names out of byte order, and a header naming another
#     commit, another count, another ref, a ref that only begins the same way,
#     or one whose dots are other characters (the compare is not a pattern);
#   - a record pinned at a ref that is not a release tag fails (exit 1): a
#     branch name, a raw commit SHA, and the pair platform-compat.sh
#     --preview writes at a commit, offered as the committed pin;
#   - a record with no pinned key, no pinned ref, a short pinned commit,
#     another format or no JSON at all, and a missing list, cannot be read
#     (exit 2).
# The check runs from the temporary directory with relative paths, so the
# names it prints are the same on every machine.
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
# shellcheck source=scripts/test-lib.sh
. "$here/test-lib.sh"
check="$here/check-platform-tools.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# The passing pair: platform-compat.sh, run from a copy of the scripts (it
# writes its pin beside itself), pins a three-tool record (listed out of byte
# order) at a planted tag.
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
cp "$here"/*.sh "$tmp/scripts/"
bash "$tmp/scripts/platform-compat.sh" "$platform" v0.16.16 >/dev/null
record=scripts/platform-compat.json
list=scripts/platform-tools.txt
commit="$(jq -r '.pinned.commit' "$tmp/$record")"

# The check's answers, as it prints them.
refusal() {
  echo "check-platform-tools: FAIL, $1 is not the tool list of $record, pinned at v0.16.16. Regenerate both with scripts/platform-compat.sh; never edit either by hand."
}
header1() { echo "$1:1: the header does not name the record's 3 tools at its pinned ref, v0.16.16"; }
names() { echo "$1: its names are not the names in tools.list of $record, in byte order (diff above: < the list, > the record)"; }
unreadable() {
  echo "check-platform-tools: $1 is not a format 1 record with a pinned ref and commit and a list of tool names; regenerate it with scripts/platform-compat.sh"
}
not_a_release() {
  echo "check-platform-tools: FAIL, $1 is pinned at $2, which is not a release tag (v and a plain MAJOR.MINOR.PATCH triple). Pin a release with scripts/platform-compat.sh <platform checkout> <release tag>; a check before a release runs with --preview, whose files are never committed."
}
# tools <record> <list>: the check, run from the temporary directory.
tools() {
  cd "$tmp" && bash "$check" "$@"
}

expect "the pair platform-compat.sh writes" 0 \
  "check-platform-tools: OK (the 3 pinned tool names are the record's, at v0.16.16)" tools "$record" "$list"

grep -v '^purge_app$' "$tmp/$list" >"$tmp/missing.txt"
expect "a name gone from the list" 1 "$(echo "2a3"; echo "> purge_app"; names missing.txt; refusal missing.txt)" \
  tools "$record" missing.txt
{ cat "$tmp/$list"; echo renew_app; } >"$tmp/extra.txt"
expect "a name the record lacks" 1 "$(echo "4d3"; echo "< renew_app"; names extra.txt; refusal extra.txt)" \
  tools "$record" extra.txt
{ grep '^#' "$tmp/$list"; grep -v '^#' "$tmp/$list" | LC_ALL=C sort -r; } >"$tmp/order.txt"
expect "the names out of byte order" 1 "$(
  echo "1,2d0"; echo "< purge_app"; echo "< get_app_logs"; echo "3a2,3"; echo "> get_app_logs"; echo "> purge_app"
  names order.txt; refusal order.txt
)" tools "$record" order.txt
sed 's/(commit [0-9a-f]\{40\})/(commit 464c5f3b0000000000000000000000000000beef)/' "$tmp/$list" >"$tmp/commit.txt"
expect "a header naming another commit" 1 "$(
  echo "commit.txt:2: the header does not name the record's pinned commit, $commit"; refusal commit.txt
)" tools "$record" commit.txt
sed '1s/: 3 tools at/: 4 tools at/' "$tmp/$list" >"$tmp/count.txt"
expect "a header naming another count" 1 "$(header1 count.txt; refusal count.txt)" tools "$record" count.txt
sed '1s/ at v0\.16\.16$/ at v0.16.15/' "$tmp/$list" >"$tmp/ref.txt"
expect "a header naming another ref" 1 "$(header1 ref.txt; refusal ref.txt)" tools "$record" ref.txt
sed '1s/ at v0\.16\.16$/ at v0.16.160/' "$tmp/$list" >"$tmp/longer.txt"
expect "a header naming a ref that only begins the same way" 1 "$(header1 longer.txt; refusal longer.txt)" \
  tools "$record" longer.txt
sed '1s/ at v0\.16\.16$/ at v0x16x16/' "$tmp/$list" >"$tmp/dots.txt"
expect "a header naming the ref with its dots changed" 1 "$(header1 dots.txt; refusal dots.txt)" tools "$record" dots.txt

# A pin that is not a release, each with a list whose header names the same
# ref, so the ref is all that is wrong. CI cannot ask the platform
# repository, so the ref's form is what it checks.
jq '.pinned.ref = "main"' "$tmp/$record" >"$tmp/branch.json"
sed '1s/ at v0\.16\.16$/ at main/' "$tmp/$list" >"$tmp/branch.txt"
expect "a record pinned at a branch name" 1 "$(not_a_release branch.json main)" tools branch.json branch.txt
jq --arg c "$commit" '.pinned.ref = $c' "$tmp/$record" >"$tmp/sha.json"
sed "1s/ at v0\.16\.16\$/ at $commit/" "$tmp/$list" >"$tmp/sha.txt"
expect "a record pinned at a raw commit SHA" 1 "$(not_a_release sha.json "$commit")" tools sha.json sha.txt
# The pair a preview writes, at the tagged commit named by its SHA, offered
# as the committed pin.
preview_pair() {
  bash "$tmp/scripts/platform-compat.sh" --preview "$platform" "$commit" >/dev/null &&
    tools scripts/platform-compat.preview.json scripts/platform-tools.preview.txt
}
expect "the pair a preview writes, offered as the committed pin" 1 \
  "$(not_a_release scripts/platform-compat.preview.json "$commit")" preview_pair

jq 'del(.pinned)' "$tmp/$record" >"$tmp/nopin.json"
expect "a record with no pinned key" 2 "$(unreadable nopin.json)" tools nopin.json "$list"
jq 'del(.pinned.ref)' "$tmp/$record" >"$tmp/noref.json"
expect "a record with a pinned commit but no ref" 2 "$(unreadable noref.json)" tools noref.json "$list"
jq '.pinned.commit |= .[0:8]' "$tmp/$record" >"$tmp/short.json"
expect "a record with a short pinned commit" 2 "$(unreadable short.json)" tools short.json "$list"
jq '.format = 2' "$tmp/$record" >"$tmp/format.json"
expect "a record in format 2" 2 "$(unreadable format.json)" tools format.json "$list"
echo 'not json' >"$tmp/notjson.json"
expect "a record that is not JSON" 2 "$(unreadable notjson.json)" tools notjson.json "$list"
expect "a missing list" 2 "check-platform-tools: cannot read nosuch.txt" tools "$record" nosuch.txt

[ "$fail" -eq 0 ] || exit 1
echo "test-check-platform-tools: OK ($n cases: the pair platform-compat.sh writes passes; each planted disagreement fails, and so does a pin that is not a release tag; an unreadable record or list is refused, each with exactly its message)"
