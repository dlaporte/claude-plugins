#!/usr/bin/env bash
# Runs scripts/check-tool-names.sh on its fixture and fails unless it reports
# exactly the names the fixture plants, and exits 1. The fixture,
# scripts/fixtures/check-tool-names/skills/demo/SKILL.md, holds one line per
# rule that must fail and the look-alikes that must pass (arguments, codes,
# settings keys, "recall", shell and Python code in a fence).
# Usage (from the repo root): bash scripts/test-check-tool-names.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
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

rc=0
out="$(cd "$here/.." && bash scripts/check-tool-names.sh "$fixture" 2>/dev/null)" || rc=$?
got="$(printf '%s\n' "$out" | sed -n 's/^\(.*: `[a-z0-9_]*`\) is .*/\1/p' | LC_ALL=C sort)"

fail=0
if [ "$rc" -ne 1 ]; then
  echo "test-check-tool-names: the check exited $rc on the fixture, expected 1" >&2
  fail=1
fi
if [ "$got" != "$expected" ]; then
  echo "test-check-tool-names: the check reported a different set of names than the fixture plants:" >&2
  diff <(printf '%s\n' "$expected") <(printf '%s\n' "$got") >&2 || true
  fail=1
fi
[ "$fail" -eq 0 ] || exit 1
echo "test-check-tool-names: OK ($(printf '%s\n' "$expected" | grep -c .) planted names reported, nothing else)"
