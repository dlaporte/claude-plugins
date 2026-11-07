#!/usr/bin/env bash
# Runs scripts/check-tool-names.sh on its fixture and fails unless it reports
# exactly the names the fixture plants, and exits 1. The fixture,
# scripts/fixtures/check-tool-names/skills/demo/SKILL.md, holds one line per
# rule that must fail and the look-alikes that must pass (arguments, codes,
# settings keys, "recall", shell and Python code in a fence). That run passes
# --partial, since the fixture names only a few pinned tools. A second run,
# without it, proves the reverse check: a pinned tool the fixture never names
# (purge_app) is reported, and one it names (app_status) is not. A third
# part plants a list and a plugin of its own for --pinned (below).
# Usage (from the repo root): bash scripts/test-check-tool-names.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/test-lib.sh
. "$here/test-lib.sh"
fixture="scripts/fixtures/check-tool-names"
file="$fixture/skills/demo/SKILL.md"

expected="$(LC_ALL=C sort <<EOF
$file:3: \`set_app_variabl\`
$file:8: \`list_appz\`
$file:9: \`get_app_log\`
$file:10: \`renew_app\`
$file:11: \`decommission_app\`
$file:12: \`create_app\`
$file:15: \`frobnicate_app\`
$file:16: \`register_ap\`
EOF
)"

# partial_names: the check on the fixture with --partial, its exit status,
# and of its output the names it reports (file:line: `name`, in byte order)
# and any reverse-check line, which --partial must not print.
partial_names() {
  local rc=0 out
  out="$(cd "$here/.." && bash scripts/check-tool-names.sh --partial "$fixture" 2>/dev/null)" || rc=$?
  printf '%s\n' "$out" | sed -n -e 's/^\(.*: `[a-z0-9_]*`\) is .*/\1/p' -e '/is never named$/p' | LC_ALL=C sort
  return "$rc"
}
expect "the planted names, with --partial and no reverse check" 1 "$expected" partial_names

# The reverse check, on the same fixture without --partial.
rc=0
out="$(cd "$here/.." && bash scripts/check-tool-names.sh "$fixture" 2>/dev/null)" || rc=$?
if [ "$rc" -ne 1 ]; then
  echo "test-check-tool-names: the reverse check exited $rc on the fixture, expected 1" >&2
  fail=1
fi
if ! printf '%s\n' "$out" | grep -qx "$fixture: pinned tool purge_app is never named"; then
  echo "test-check-tool-names: the reverse check did not report purge_app, which the fixture never names" >&2
  fail=1
fi
if printf '%s\n' "$out" | grep -q 'pinned tool app_status is never named'; then
  echo "test-check-tool-names: the reverse check reported app_status, which the fixture names" >&2
  fail=1
fi
# --pinned <file>: another server's list (CI runs the servicenow plugin with
# scripts/snow-tools.txt). On a list and a plugin planted here: a misspelled
# name is reported against that list and the failure names it, the tool it
# misspells is never named, and a one-word tool in backticks (snow-mcp's
# whoami) counts as named; with the misspelling fixed the run passes; the
# one-word tool written without backticks is absent, so it alone is never
# named. A missing file argument is a usage error (exit 2).
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
printf '# a planted list\nquery_records\nget_widget\nwhoami\n' >"$tmp/tools.txt"
mkdir -p "$tmp/plugin/skills/demo"
# plant_skill <how whoami is written> <the get_ name>
plant_skill() {
  printf -- '---\nname: demo\ndescription: Planted by scripts/test-check-tool-names.sh.\n---\n\nCall %s, then `query_records(table="incident")` and `%s`.\n' "$1" "$2" >"$tmp/plugin/skills/demo/SKILL.md"
}
plant_skill '`whoami`' get_widgte
rc=0
out="$(cd "$here/.." && bash scripts/check-tool-names.sh --pinned "$tmp/tools.txt" "$tmp/plugin" 2>&1)" || rc=$?
got="$(printf '%s\n' "$out" | sed -n 's/^\(.*: `[a-z0-9_]*`\) is .*/\1/p')"
if [ "$rc" -ne 1 ] || [ "$got" != "$tmp/plugin/skills/demo/SKILL.md:6: \`get_widgte\`" ]; then
  echo "test-check-tool-names: --pinned exited $rc and reported '$got', expected 1 and the planted get_widgte alone:" >&2
  printf '%s\n' "$out" >&2
  fail=1
fi
if ! printf '%s\n' "$out" | grep -qx "$tmp/plugin: pinned tool get_widget is never named"; then
  echo "test-check-tool-names: --pinned did not report get_widget, which the planted plugin only misspells" >&2
  fail=1
fi
if printf '%s\n' "$out" | grep -qE 'pinned tool (whoami|query_records) is never named'; then
  echo "test-check-tool-names: --pinned reported whoami or query_records, which the planted plugin names" >&2
  fail=1
fi
if ! printf '%s\n' "$out" | grep -qF "not in $tmp/tools.txt."; then
  echo "test-check-tool-names: the --pinned failure does not name the list it checked against" >&2
  fail=1
fi
plant_skill '`whoami`' get_widget
rc=0
out="$(cd "$here/.." && bash scripts/check-tool-names.sh --pinned "$tmp/tools.txt" "$tmp/plugin" 2>&1)" || rc=$?
if [ "$rc" -ne 0 ] || [ "$out" != "check-tool-names: OK ($tmp/plugin, 3 pinned tools, all named)" ]; then
  echo "test-check-tool-names: --pinned on the corrected plugin exited $rc, expected 0 and the OK line:" >&2
  printf '%s\n' "$out" >&2
  fail=1
fi
plant_skill whoami get_widget
rc=0
out="$(cd "$here/.." && bash scripts/check-tool-names.sh --pinned "$tmp/tools.txt" "$tmp/plugin" 2>/dev/null)" || rc=$?
if [ "$rc" -ne 1 ] || [ "$out" != "$tmp/plugin: pinned tool whoami is never named" ]; then
  echo "test-check-tool-names: --pinned with whoami out of backticks exited $rc and said '$out', expected 1 and whoami alone never named" >&2
  fail=1
fi
rc=0
out="$(cd "$here/.." && bash scripts/check-tool-names.sh --pinned 2>&1)" || rc=$?
if [ "$rc" -ne 2 ] || [ "$out" != "check-tool-names: --pinned needs a file" ]; then
  echo "test-check-tool-names: --pinned with no file exited $rc and said '$out', expected 2 and the usage error" >&2
  fail=1
fi

[ "$fail" -eq 0 ] || exit 1
echo "test-check-tool-names: OK ($(printf '%s\n' "$expected" | grep -c .) planted names reported, nothing else; the reverse check reports an unnamed pinned tool; --pinned checks against the list it is given)"
