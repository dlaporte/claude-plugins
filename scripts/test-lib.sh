#!/usr/bin/env bash
# Sourced by every scripts/test-*.sh but scripts/test-starter.sh, the
# starter's runtime suite, which asserts in node's test runner over
# scripts/starter-test/*.test.mjs rather than case by case here: the harness
# they share, as scripts/lib.sh holds what the checks share.
#
#   expect <label> <exit> <output> <command> [arg ...]
#
# runs the command, its stderr joined to its stdout, and records a failure
# unless its exit status and its whole output are exactly the ones given: it
# prints the label, the two statuses and a diff (< expected, > got) to stderr,
# and sets fail=1. n counts the cases. The command may be a function of the
# test's own; it runs in a subshell, so a cd in it stays there. Where a
# whole output is not fixed (test-check-tool-names.sh's reverse check lists
# whichever pinned tools its fixture never names, so a resync moves it), a
# test asserts on the lines it needs and sets fail=1 itself. A test ends with
# [ "$fail" -eq 0 ] || exit 1 and its OK line. Messages begin with the test's
# name, its file name without .sh.
#
# Run rather than sourced (bash scripts/test-lib.sh), it proves expect on
# itself, and scripts/lib.sh's helpers on cases it plants: an exact match
# passes, and a wrong exit status or a wrong output is reported with exactly
# its lines; grep_or_none passes a match and no match and stops the check on
# a grep error; require_jq stops a check that has no jq; sha256_of prints a
# known input's hash, by either tool; join_names lists one, two and three
# names as a message does.
test_name="$(basename "$0" .sh)"
fail=0
n=0
expect() {
  local label="$1" want_rc="$2" want="$3" rc=0 out
  shift 3
  n=$((n + 1))
  out="$("$@" 2>&1)" || rc=$?
  if [ "$rc" -ne "$want_rc" ] || [ "$out" != "$want" ]; then
    echo "$test_name: $label: exited $rc (expected $want_rc); its output against the expected (< expected, > got):" >&2
    diff <(printf '%s\n' "$want") <(printf '%s\n' "$out") >&2 || true
    fail=1
  fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -euo pipefail
  here="$(cd "$(dirname "$0")" && pwd)"
  # Sourced before the trap is set: under bash 3.2 a failed source after an
  # EXIT trap exits 0, so a missing lib.sh would read as a pass.
  # shellcheck source=scripts/lib.sh
  . "$here/lib.sh"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  # report <expect's arguments>: what expect prints for them, and fail after it.
  report() {
    fail=0
    expect "$@" 2>&1
    echo "fail=$fail"
  }
  differs="$test_name: planted: exited"
  expect "an exact match passes" 0 "fail=0" report planted 0 hello echo hello
  expect "a wrong exit status is reported" 0 "$(
    echo "$differs 1 (expected 0); its output against the expected (< expected, > got):"
    echo "fail=1"
  )" report planted 0 "" false
  expect "a wrong output is reported, as a diff" 0 "$(
    echo "$differs 0 (expected 0); its output against the expected (< expected, > got):"
    printf '%s\n' 1c1 "< hello" --- "> help" "fail=1"
  )" report planted 0 hello echo help

  printf 'a\nb\n' >"$tmp/ab"
  expect "grep_or_none prints a match" 0 "a" grep_or_none -x a "$tmp/ab"
  expect "grep_or_none passes no match" 0 "" grep_or_none -x c "$tmp/ab"
  expect "grep_or_none stops the check on a grep error" 2 "$test_name: grep failed (2)" \
    grep_or_none -s -x a "$tmp/absent"
  # A PATH with no jq on it, in expect's subshell alone.
  without_jq() {
    # shellcheck disable=SC2123
    PATH=/nonexistent
    require_jq
  }
  expect "require_jq passes with jq on the PATH" 0 "" require_jq
  expect "require_jq stops a check that has no jq" 2 "$test_name: jq is required" without_jq
  # sha256 of "abc" (FIPS 180-2's example), from either tool: a PATH holding
  # only shasum and the tools around it shows the macOS branch on Linux too,
  # wherever shasum is installed (a host without it never takes that branch).
  abc() { printf abc | sha256_of; }
  abc_by_shasum() {
    mkdir -p "$tmp/bin"
    local t
    for t in shasum cut perl; do
      if command -v "$t" >/dev/null; then ln -sf "$(command -v "$t")" "$tmp/bin/$t"; fi
    done
    PATH="$tmp/bin"
    abc
  }
  abc_hash=ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
  expect "sha256_of prints its input's hash" 0 "$abc_hash" abc
  if command -v shasum >/dev/null; then
    expect "sha256_of prints it by shasum where there is no sha256sum" 0 "$abc_hash" abc_by_shasum
  fi
  expect "join_names lists one name" 0 "a" join_names a
  expect "join_names lists two names" 0 "a and b" join_names a b
  expect "join_names lists three names" 0 "a, b and c" join_names a b c

  [ "$fail" -eq 0 ] || exit 1
  echo "$test_name: OK ($n cases: expect passes an exact match and reports a wrong exit status or output; grep_or_none, require_jq, sha256_of and join_names each do what the checks rely on)"
fi
