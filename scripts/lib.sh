# Sourced, never run: the helpers the checks share, as scripts/semver.sh holds
# a version's shape. A check sources it with
#   . "$(cd "$(dirname "$0")" && pwd)/lib.sh"
# before it sets any EXIT trap: under bash 3.2 a failed source after one
# exits 0. Messages begin with the check's own name, its file name without
# .sh. scripts/test-lib.sh, run, proves each helper.
script_name="$(basename "$0" .sh)"

# require_jq: exits 2, naming the check, when jq is not on the PATH.
require_jq() {
  if ! command -v jq >/dev/null; then
    echo "$script_name: jq is required" >&2
    exit 2
  fi
}

# grep_or_none <grep argument>...: grep, for which no match (its exit 1) is
# not an error: prints the matches, if any, and returns 0. A grep error (exit
# 2) exits 2, naming the check; called inside $(...), that exit ends the
# subshell, and set -e then ends the check with the same status.
grep_or_none() {
  local rc=0
  grep "$@" || rc=$?
  if [ "$rc" -gt 1 ]; then
    echo "$script_name: grep failed ($rc)" >&2
    exit 2
  fi
}

# join_names <name>...: the names as a message lists them: "a", "a and b",
# "a, b and c".
join_names() {
  local out="$1"
  if [ $# -gt 1 ]; then
    out="$(printf '%s, ' "${@:1:$#-1}")"
    out="${out%, } and ${!#}"
  fi
  printf '%s\n' "$out"
}
