#!/usr/bin/env bash
# Runs scripts/version-bump.sh, the version-bump gate, on a repository this
# script plants in a temporary directory, and fails unless the gate's whole
# output and exit status are exactly what each planted change calls for.
#
# The base commit holds five plugins. The first run's change must pass: a
# patch bump (kept, 1.0.0 to 1.0.1), a numeric rather than string compare
# (ordered, 1.9.0 to 1.10.0), and two new plugins (good at 0.1.0, ninedigit
# at 0.0.123456789, nine digits being the most a field may hold). The second
# run's change adds what the gate must refuse beside those:
#   - a changed plugin with no readable version: no plugin.json at all, no
#     version key, null, a number, a v prefix, a pre-release suffix, a
#     trailing newline, a ten-digit field (bigfield), and a pre-release on a
#     plugin present at the base (kept-bad);
#   - a changed plugin whose version did not go up: an edit with the version
#     unchanged (unbumped) and a lowered version (lowered, 1.2.0 to 1.1.9).
# The gate runs under LC_ALL=C, so it visits the plugins in a fixed order:
# byte order of "plugins/<name>/", which puts kept-bad before kept.
# Usage (from the repo root): bash scripts/test-version-bump.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
gate="$here/version-bump.sh"
repo="$(mktemp -d)"
trap 'rm -rf "$repo"' EXIT

g() {
  git -C "$repo" -c user.name=test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"
}
# plant <plugin> [manifest JSON]: a README, and the manifest when one is given.
plant() {
  mkdir -p "$repo/plugins/$1"
  printf '%s\n' "$1" >"$repo/plugins/$1/README.md"
  if [ $# -gt 1 ]; then
    mkdir -p "$repo/plugins/$1/.claude-plugin"
    printf '%s' "$2" >"$repo/plugins/$1/.claude-plugin/plugin.json"
  fi
}
# version <plugin> <version JSON>: the manifest alone, rewritten.
version() {
  printf '{"name":"%s","version":%s}' "$1" "$2" >"$repo/plugins/$1/.claude-plugin/plugin.json"
}
commit() {
  g add -A
  g commit -q -m "$1"
  g rev-parse HEAD
}
# The gate's two refusals, as it prints them.
unreadable() {
  printf '::error file=plugins/%s/.claude-plugin/plugin.json::"%s" changed but has no readable .claude-plugin/plugin.json version\n' "$1" "$1"
}
not_bumped() {
  printf '::error file=plugins/%s/.claude-plugin/plugin.json::"%s" changed but its version is still %s: bump it. Delivery is keyed on this value, so users already on %s may never receive these changes.\n' "$1" "$1" "$2" "$2"
  printf '  changed files:\n'
  printf '    plugins/%s/%s\n' "$1" "$3"
}
fail=0
# check <label> <base> <expected exit> <expected output>
check() {
  local rc=0 out
  out="$(cd "$repo" && LC_ALL=C BASE_SHA="$2" bash "$gate" 2>&1)" || rc=$?
  if [ "$rc" -ne "$3" ] || [ "$out" != "$4" ]; then
    echo "test-version-bump: $1: the gate exited $rc (expected $3), and its output differs from what the fixture plants:" >&2
    diff <(printf '%s\n' "$4") <(printf '%s\n' "$out") >&2 || true
    fail=1
  fi
}

g init -q -b main
plant kept '{"name":"kept","version":"1.0.0"}'
plant kept-bad '{"name":"kept-bad","version":"1.0.0"}'
plant ordered '{"name":"ordered","version":"1.9.0"}'
plant unbumped '{"name":"unbumped","version":"1.0.0"}'
plant lowered '{"name":"lowered","version":"1.2.0"}'
base="$(commit base)"

# Run 1: only good changes, so the gate passes.
version kept '"1.0.1"'
version ordered '"1.10.0"'
plant good '{"name":"good","version":"0.1.0"}'
plant ninedigit '{"name":"ninedigit","version":"0.0.123456789"}'
commit good >/dev/null
check "a good change" "$base" 0 "$(
  echo "OK: good (unversioned) -> 0.1.0"
  echo "OK: kept 1.0.0 -> 1.0.1"
  echo "OK: ninedigit (unversioned) -> 0.0.123456789"
  echo "OK: ordered 1.9.0 -> 1.10.0"
)"

# Run 2: the planted refusals, beside the good changes above.
plant bigfield '{"name":"bigfield","version":"1.0.1234567890"}'
version kept-bad '"1.0.1-beta"'
version lowered '"1.1.9"'
plant missing-key '{"name":"missing-key"}'
plant missing-manifest
plant null-version '{"name":"null-version","version":null}'
plant numeric-version '{"name":"numeric-version","version":1}'
plant pre-release '{"name":"pre-release","version":"1.0.0-beta"}'
plant trailing-newline '{"name":"trailing-newline","version":"1.0.0\n"}'
printf 'an edit\n' >>"$repo/plugins/unbumped/README.md"
plant v-prefix '{"name":"v-prefix","version":"v1.0.0"}'
commit bad >/dev/null
check "the planted refusals" "$base" 1 "$(
  unreadable bigfield
  echo "OK: good (unversioned) -> 0.1.0"
  unreadable kept-bad
  echo "OK: kept 1.0.0 -> 1.0.1"
  not_bumped lowered 1.1.9 .claude-plugin/plugin.json
  unreadable missing-key
  unreadable missing-manifest
  echo "OK: ninedigit (unversioned) -> 0.0.123456789"
  unreadable null-version
  unreadable numeric-version
  echo "OK: ordered 1.9.0 -> 1.10.0"
  unreadable pre-release
  unreadable trailing-newline
  not_bumped unbumped 1.0.0 README.md
  unreadable v-prefix
)"

[ "$fail" -eq 0 ] || exit 1
echo "test-version-bump: OK (a good change passes; 9 unreadable versions and 2 versions that did not go up are refused, nothing else)"
