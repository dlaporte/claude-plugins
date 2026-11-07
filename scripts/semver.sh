# Sourced, never run: the one home for a version's shape, its reading and its
# comparison. scripts/plugin-version.sh and scripts/check-plugin-floor.sh read
# a version from JSON with semver_json, check-plugin-floor.sh compares the
# plugin with the platform's floor with semver_at_least,
# scripts/version-bump.sh compares a plugin's new version with its old one
# with semver_above, and scripts/platform-compat.sh and
# scripts/check-platform-tools.sh tell a platform release tag with
# semver_release_tag.
#
# A version is a plain MAJOR.MINOR.PATCH triple with at most nine digits in
# each field: the shape CLAUDE.md allows, and the one the Innovation Platform
# parses (compareSemver in inno-platform's src/util.ts reads \d{1,9} per
# field and answers anything else "unparseable").
SEMVER_TRIPLE='^([0-9]{1,9})\.([0-9]{1,9})\.([0-9]{1,9})$'

# semver_json <file> <jq path>: prints the value at the path and returns 0
# when it is a JSON string whose inside is a plain triple. Otherwise it prints
# nothing and returns 1: an unreadable file, a missing value, null, a number,
# or a string of another shape, whitespace included.
#
# The value is read as JSON (jq -c), not raw (jq -r): a raw read inside $(...)
# loses a trailing newline and passes "1.2.3\n", and jq's own regex anchors
# match at a line end. Encoded, a newline stays the two characters \n, a
# number or null carries no quotes, and a file of two JSON documents reads as
# two lines, so only one quoted string whose inside is a triple passes.
semver_json() {
  local raw version
  raw="$(jq -c "$2" "$1" 2>/dev/null)" || return 1
  [[ "$raw" =~ ^\"(.*)\"$ ]] || return 1
  version="${BASH_REMATCH[1]}"
  [[ "$version" =~ $SEMVER_TRIPLE ]] || return 1
  printf '%s\n' "$version"
}

# semver_release_tag <ref>: true when the ref has a platform release tag's
# form, v and a plain triple (v0.18.14). The platform's release tags have it
# (release.tagPattern, v* upstream); a branch, a raw commit SHA and a
# pre-release or instance tag (v0.18.14-rc.1) do not.
semver_release_tag() {
  [ "${1:0:1}" = v ] && [[ "${1:1}" =~ $SEMVER_TRIPLE ]]
}

# semver_order A B: prints -1, 0 or 1 as A is below, equal to or above B,
# comparing field by field as numbers, so 2.10.0 is above 2.9.0. 10# reads a
# field with a leading zero (09) as decimal, not octal. Prints nothing and
# returns 1 when either is not a plain triple.
semver_order() {
  local a1 a2 a3
  [[ "$1" =~ $SEMVER_TRIPLE ]] || return 1
  a1="${BASH_REMATCH[1]}"; a2="${BASH_REMATCH[2]}"; a3="${BASH_REMATCH[3]}"
  [[ "$2" =~ $SEMVER_TRIPLE ]] || return 1
  local -a a=("$a1" "$a2" "$a3") b=("${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}")
  local i
  for i in 0 1 2; do
    if ((10#${a[i]} != 10#${b[i]})); then
      if ((10#${a[i]} > 10#${b[i]})); then echo 1; else echo -1; fi
      return 0
    fi
  done
  echo 0
}

# semver_at_least A B: true when A is at or above B. False when either is not
# a plain triple.
semver_at_least() {
  local order
  order="$(semver_order "$1" "$2")" || return 1
  [ "$order" != -1 ]
}

# semver_above A B: true when A is above B. False when either is not a plain
# triple, so a version of another shape never reads as a bump.
semver_above() {
  local order
  order="$(semver_order "$1" "$2")" || return 1
  [ "$order" = 1 ]
}
