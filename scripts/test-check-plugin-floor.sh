#!/usr/bin/env bash
# Runs scripts/check-plugin-floor.sh on records and manifests this script
# plants in a temporary directory, and fails unless the check's whole output
# and exit status are exactly what each calls for:
#   - at or above the floor passes, including where a text compare would
#     fail (2.10.0 against 2.9.0, 10.0.0 against 9.0.0);
#   - below the floor fails, including where a text compare would pass
#     (2.9.0 against 2.10.0, 2.0.9 against 2.0.10);
#   - a field with a leading zero is read as decimal: 2.09.0 is above 2.8.0
#     and below 2.10.0 (without 10#, bash reads 09 as a bad octal number, the
#     field compare errors, and the second case would pass);
#   - a floor or a plugin version that is not a plain triple, or is missing,
#     cannot be read (exit 2), and the message names the file.
# Usage (from the repo root): bash scripts/test-check-plugin-floor.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
check="$here/check-plugin-floor.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
n=0
record="$tmp/record.json"
plugin="$tmp/plugin.json"
# The check's four answers, as it prints them.
ok() { echo "check-plugin-floor: OK (the plugin's $1 is at least $2, the app plugin floor at vtest)"; }
below() {
  echo "check-plugin-floor: FAIL, the plugin's $1 is below $2, the app plugin floor (plugins.app.minVersion) at vtest. Resync the plugin with that release and bump its version to at least $2."
}
no_floor() { echo "check-plugin-floor: $record holds no plain MAJOR.MINOR.PATCH plugins.app.minVersion"; }
no_version() { echo "check-plugin-floor: $plugin declares no plain MAJOR.MINOR.PATCH version"; }
# expect <plugin version JSON> <floor JSON> <expected exit> <expected output>
expect() {
  local rc=0 out
  n=$((n + 1))
  printf '{"name":"demo","version":%s}\n' "$1" >"$plugin"
  printf '{"plugins":{"app":{"minVersion":%s}},"pinned":{"ref":"vtest"}}\n' "$2" >"$record"
  out="$(bash "$check" "$record" "$plugin" 2>&1)" || rc=$?
  if [ "$rc" -ne "$3" ] || [ "$out" != "$4" ]; then
    echo "test-check-plugin-floor: plugin $1 against floor $2 exited $rc (expected $3), and its output differs:" >&2
    diff <(printf '%s\n' "$4") <(printf '%s\n' "$out") >&2 || true
    fail=1
  fi
}

expect '"2.1.0"' '"2.0.0"' 0 "$(ok 2.1.0 2.0.0)"
expect '"2.0.0"' '"2.0.0"' 0 "$(ok 2.0.0 2.0.0)"
expect '"2.10.0"' '"2.9.0"' 0 "$(ok 2.10.0 2.9.0)"
expect '"10.0.0"' '"9.0.0"' 0 "$(ok 10.0.0 9.0.0)"
expect '"3.0.0"' '"2.99.99"' 0 "$(ok 3.0.0 2.99.99)"
expect '"2.09.0"' '"2.8.0"' 0 "$(ok 2.09.0 2.8.0)"
expect '"2.09.0"' '"2.10.0"' 1 "$(below 2.09.0 2.10.0)"
expect '"2.9.0"' '"2.10.0"' 1 "$(below 2.9.0 2.10.0)"
expect '"2.0.9"' '"2.0.10"' 1 "$(below 2.0.9 2.0.10)"
expect '"1.99.99"' '"2.0.0"' 1 "$(below 1.99.99 2.0.0)"
expect '"2.0.0"' '"2.0.1"' 1 "$(below 2.0.0 2.0.1)"
expect '"2.1.0"' '"v2.0.0"' 2 "$(no_floor)"
expect '"2.1.0"' '"2.0"' 2 "$(no_floor)"
expect '"2.1.0"' 'null' 2 "$(no_floor)"
expect '"2.1.0"' '200' 2 "$(no_floor)"
expect '"2.1"' '"2.0.0"' 2 "$(no_version)"

[ "$fail" -eq 0 ] || exit 1
echo "test-check-plugin-floor: OK ($n cases: at or above the floor passes, below fails, compared as numbers; an unreadable version is refused, each with exactly its message)"
