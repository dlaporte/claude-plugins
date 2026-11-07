#!/usr/bin/env bash
# Runs scripts/check-tool-names.sh on its fixture and fails unless it reports
# exactly the names the fixture plants, and exits 1. The fixture,
# scripts/fixtures/check-tool-names/skills/demo/SKILL.md, holds one line per
# rule that must fail and the look-alikes that must pass (arguments, codes,
# settings keys, "recall", shell and Python code in a fence). That run passes
# --partial, since the fixture names only a few pinned tools. A second run,
# without it, proves the reverse check: a pinned tool the fixture never names
# (purge_app) is reported, and one it names (app_status) is not.
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
[ "$fail" -eq 0 ] || exit 1
echo "test-check-tool-names: OK ($(printf '%s\n' "$expected" | grep -c .) planted names reported, nothing else; the reverse check reports an unnamed pinned tool)"
