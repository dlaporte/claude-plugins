#!/usr/bin/env bash
# Fails if the innovation-platform plugin asks get_app_contract for a section
# the platform's contract does not have. The contract's section ids are
# pinned in scripts/platform-compat.json (contract.sections of the platform's
# compatibility record, refreshed at each resync by
# scripts/platform-compat.sh), so this needs no platform checkout. Without it
# a renumbered contract would leave a skill asking for a section that is gone,
# and nothing would say so.
#
# Usage: bash scripts/check-contract-sections.sh [path] [record]
#   (default plugins/innovation-platform and scripts/platform-compat.json)
#
# A literal is `sections: [` (or the JSON key "sections": [) up to the first
# `]` on the same line, in any text file under path; a line may hold more
# than one, even glued to the one before it. The key must start a word, so
# `subsections: [` is not one. Each element of it must be a double-quoted id
# the record's contract has. Prints file:line: and what is wrong, once per bad
# element, and exits 1 if there is any:
#   - an id that is not numbers joined by dots, such as "1.3 2", which would
#     otherwise match two ids side by side in the record's list;
#   - an id the pinned contract does not have;
#   - an element that is not a quoted string;
#   - a literal with no `]` on its line, which this cannot read, so it fails
#     rather than pass unread.
# A list with no sections key (`["2"]` alone), an id after the literal and a
# section sign in prose are not checked.
# scripts/test-check-contract-sections.sh holds a fixture for each of these.
set -euo pipefail

if ! command -v jq >/dev/null; then
  echo "check-contract-sections: jq is required" >&2
  exit 2
fi

target="${1:-plugins/innovation-platform}"
here="$(cd "$(dirname "$0")" && pwd)"
record="${2:-$here/platform-compat.json}"

if [ ! -d "$target" ]; then
  echo "check-contract-sections: no such directory: $target" >&2
  exit 2
fi
# Space-joined with a space at each end, so " $id " matches one whole id.
if ! known="$(jq -er '.contract.sections
    | if type == "array" and length > 0 and all(.[]; type == "string") then " " + join(" ") + " " else error("") end' \
    "$record" 2>/dev/null)"; then
  echo "check-contract-sections: cannot read contract.sections from $record" >&2
  exit 2
fi
pinned="$(jq -r '"contract \(.contract.version) at \(.pinned.ref)"' "$record")"

# grep exits 1 for "no match", which is not an error here; 2 is. -I skips
# binary files. The match takes in the whole word that ends in sections, and
# the loop skips a longer word (subsections). Matching a boundary character
# before the key instead would miss a literal glued to the one before it,
# whose ] that match has already taken.
rc=0
literals="$(LC_ALL=C grep -rnoIE \
  '[A-Za-z0-9_]*sections"?[[:space:]]*:[[:space:]]*\[[^]]*(\]|$)' -- "$target")" || rc=$?
if [ "$rc" -gt 1 ]; then
  echo "check-contract-sections: grep failed ($rc)" >&2
  exit 2
fi

idshape='^[0-9]+(\.[0-9]+)*$'
nliterals=0
nids=0
report=""
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  # <file>:<line>:<literal>
  file="${hit%%:*}"; rest="${hit#*:}"
  line="${rest%%:*}"; literal="${rest#*:}"
  case "$literal" in
    sections*) ;;
    *) continue ;;
  esac
  nliterals=$((nliterals + 1))
  case "$literal" in
    *"]") ;;
    *)
      report+="$file:$line: a sections literal does not close on its line, so it cannot be read; keep it on one line"$'\n'
      continue
      ;;
  esac
  body="${literal#*[}"; body="${body%]}"
  set -f; old_ifs="$IFS"; IFS=,
  for element in $body; do
    IFS="$old_ifs"
    # Trim the spaces around it.
    element="${element#"${element%%[![:space:]]*}"}"
    element="${element%"${element##*[![:space:]]}"}"
    [ -n "$element" ] || continue
    case "$element" in
      \"*\")
        id="${element#\"}"; id="${id%\"}"
        nids=$((nids + 1))
        if [[ ! $id =~ $idshape ]]; then
          report+="$file:$line: \"$id\" is not a section id: an id is numbers joined by dots"$'\n'
          continue
        fi
        case "$known" in
          *" $id "*) ;;
          *) report+="$file:$line: \"$id\" is not a section of the pinned contract"$'\n' ;;
        esac
        ;;
      *) report+="$file:$line: $element is not a quoted section id"$'\n' ;;
    esac
  done
  IFS="$old_ifs"; set +f
done <<<"$literals"

if [ -n "$report" ]; then
  # By file, then by line number, so the report reads the same on any grep.
  printf '%s' "$report" | LC_ALL=C sort -t: -k1,1 -k2,2n
  echo "check-contract-sections: FAIL, $(printf '%s' "$report" | grep -c .) element(s) above are not sections of $pinned (${record#"$PWD"/}). Fix the id, or if the platform renumbered its contract, resync with scripts/platform-compat.sh and read the contract's history." >&2
  exit 1
fi
echo "check-contract-sections: OK ($target, $nliterals literal(s) asking for $nids section(s), all in $pinned)"
