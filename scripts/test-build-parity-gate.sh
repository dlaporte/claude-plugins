#!/usr/bin/env bash
# Runs scripts/test-build-parity.sh's gate, the part that decides whether a
# platform builder may run, on records and a platform checkout this script
# plants, offline, and fails unless each exit status and output is what the
# case calls for, and no planted builder ever ran:
#   - a record with no shipped key, or none for ci/build-ui.mjs, fails
#     closed, naming the release the key comes in, before any fetch;
#   - --platform on a checkout whose ci/build-ui.mjs, at the record's pinned
#     commit, has another sha256 than the record's fails, naming both, before
#     anything is installed or run;
#   - a record whose pinned commit the checkout lacks, --platform with no
#     checkout, and a record that is not JSON exit 2.
# The planted builder, run, writes a file (a control case shows it does), and
# every other case's output ends with whether it did. The cases where the
# gate passes need the npm registry, and the build-parity job runs them right
# after this.
# Usage (from the repo root): bash scripts/test-build-parity-gate.sh
set -euo pipefail
for v in "${!GIT_@}"; do unset "$v"; done
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/test-lib.sh
. "$here/test-lib.sh"
# shellcheck source=scripts/lib.sh
. "$here/lib.sh"
parity="$here/test-build-parity.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
record="$tmp/record.json"
ran="$tmp/ran"

# A platform checkout whose ci/build-ui.mjs, run or imported, writes $ran.
platform="$tmp/platform"
mkdir -p "$platform/ci"
printf '%s\n' "import { writeFileSync } from \"node:fs\";" "writeFileSync(\"$ran\", \"the planted builder ran\\n\");" \
  >"$platform/ci/build-ui.mjs"
g() {
  git -C "$platform" -c user.name=test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"
}
g init -q
g add -A
g commit -q -m planted
commit="$(g rev-parse HEAD)"
planted_hash="$(sha256_of <"$platform/ci/build-ui.mjs")"
other=0000000000000000000000000000000000000000000000000000000000000000

# gate <record JSON> <argument>...: the parity run on a record planted with
# the JSON, then whether the planted builder ran.
gate() {
  local rc=0
  printf '%s\n' "$1" >"$record"
  shift
  rm -f "$ran"
  bash "$parity" "$@" 2>&1 || rc=$?
  if [ -e "$ran" ]; then echo "the planted builder ran"; else echo "nothing ran"; fi
  return "$rc"
}
rec() { printf '{"pinned":{"ref":"vtest","commit":"%s"},"shipped":{"ci/build-ui.mjs":"%s"}}' "$1" "$2"; }
# The control: the planted builder, run, does write its file.
run_planted() {
  rm -f "$ran"
  node "$platform/ci/build-ui.mjs"
  cat "$ran"
}
expect "the planted builder, run, writes its file" 0 "the planted builder ran" run_planted

none="test-build-parity: FAIL, $record (vtest) holds no sha256 for ci/build-ui.mjs under shipped: pin a platform release from v0.18.18 on"

expect "a record with no shipped key fails closed" 1 "$none
nothing ran" gate '{"pinned":{"ref":"vtest","commit":"'"$commit"'"},"served":{}}' --platform "$platform" "$record"
expect "a record with no entry for ci/build-ui.mjs fails closed" 1 "$none
nothing ran" gate '{"pinned":{"ref":"vtest","commit":"'"$commit"'"},"shipped":{"ci/fixtures/template/scaffold/function/app/identity.ts":"'"$other"'"}}' --platform "$platform" "$record"
expect "a record with no shipped key fails closed before the mirror is fetched" 1 "$none
nothing ran" gate '{"pinned":{"ref":"vtest"},"served":{}}' "$record"
expect "a builder whose sha256 is not the record's never runs" 1 "test-build-parity: FAIL, ci/build-ui.mjs from $platform at vtest (commit $commit) has the sha256 $planted_hash, and the record at vtest names $other
nothing ran" gate "$(rec "$commit" "$other")" --platform "$platform" "$record"
expect "a pinned commit the checkout lacks" 2 "test-build-parity: $platform has no ci/build-ui.mjs at the record's pinned commit ($other); fetch it first
nothing ran" gate "$(rec "$other" "$planted_hash")" --platform "$platform" "$record"
expect "--platform with no checkout" 2 "test-build-parity: --platform needs a platform checkout
nothing ran" gate "$(rec "$commit" "$planted_hash")" --platform "$tmp/absent" "$record"
expect "a record that is not JSON" 2 "test-build-parity: $record is not readable JSON
nothing ran" gate 'nope' --platform "$platform" "$record"

[ "$fail" -eq 0 ] || exit 1
echo "test-build-parity-gate: OK ($n cases: a record with no sha256 for ci/build-ui.mjs fails closed before any fetch; a builder with another sha256 than the record's fails, naming both, and never runs; a missing commit or checkout and an unreadable record are refused, each with exactly its message)"
