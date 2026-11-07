#!/usr/bin/env bash
# Runs scripts/check-manifests.sh on repositories this script plants in a
# temporary directory, and fails unless the check's whole output and exit
# status are exactly what each calls for:
#   - a good repository passes: two plugins whose manifests are well-formed, a
#     catalog that lists both with their descriptions, and a README table
#     whose rows carry the same;
#   - a bad manifest fails, naming it: not JSON, not an object, a description
#     missing, a name that is not its directory's, a version that is not a
#     plain triple (v1.0.0); a manifest that cannot give its description is
#     not compared with the catalog or the README as well;
#   - a catalog that is not JSON, or holds no list of plugins, fails, and its
#     descriptions are not compared;
#   - a catalog entry whose description differs from its plugin.json's fails,
#     and so does one whose source has no plugin.json;
#   - a README row whose description differs fails, naming its line, and so
#     do a plugin the table lacks and a plugin with two rows.
# Usage (from the repo root): bash scripts/test-check-manifests.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/test-lib.sh
. "$here/test-lib.sh"
check="$here/check-manifests.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

alpha='Alpha does one thing.'
beta='Beta does another.'
# good <repo>: the passing repository.
good() {
  local d="$tmp/$1"
  mkdir -p "$d/plugins/alpha/.claude-plugin" "$d/plugins/beta/.claude-plugin" "$d/.claude-plugin"
  printf '{"name":"alpha","version":"1.0.0","description":"%s"}\n' "$alpha" >"$d/plugins/alpha/.claude-plugin/plugin.json"
  printf '{"name":"beta","version":"2.10.0","description":"%s"}\n' "$beta" >"$d/plugins/beta/.claude-plugin/plugin.json"
  printf '{"name":"demo","plugins":[{"name":"alpha","source":"./plugins/alpha","description":"%s"},{"name":"beta","source":"./plugins/beta","description":"%s"}]}\n' \
    "$alpha" "$beta" >"$d/.claude-plugin/marketplace.json"
  printf '%s\n' '# demo' '' '| Plugin | Description |' '|---|---|' \
    "| [\`alpha\`](plugins/alpha) | $alpha |" "| [\`beta\`](plugins/beta) | $beta |" >"$d/README.md"
}
# write <repo> <path> <content>: one file of a planted repository, replaced.
write() {
  printf '%s\n' "$3" >"$tmp/$1/$2"
}
# manifests <repo>: the check, run from the planted repository's root.
manifests() {
  cd "$tmp/$1" && bash "$check"
}
a=plugins/alpha/.claude-plugin/plugin.json
b=plugins/beta/.claude-plugin/plugin.json
catalog=.claude-plugin/marketplace.json
refusal="check-manifests: FAIL, a manifest, the catalog or the README's table above is malformed or disagrees. A plugin's description lives in its plugin.json: the catalog entry and the README row copy it word for word."

good good
expect "a good repository" 0 \
  "check-manifests: OK (2 plugin manifests; the catalog's 2 entries and the README's table carry their plugin.json descriptions)" \
  manifests good

good notjson
write notjson "$a" '{"name":"alpha",'
expect "a manifest that is not JSON" 1 "$(
  echo "::error file=$a::not valid JSON"
  echo "$refusal"
)" manifests notjson

good array
write array "$a" '["alpha"]'
expect "a manifest that is not an object" 1 "$(
  echo "::error file=$a::not a JSON object"
  echo "$refusal"
)" manifests array

good nodesc
write nodesc "$b" '{"name":"beta","version":"2.10.0"}'
expect "a manifest with no description" 1 "$(
  echo "::error file=$b::missing required field \"description\""
  echo "$refusal"
)" manifests nodesc

good name
write name "$a" "{\"name\":\"gamma\",\"version\":\"1.0.0\",\"description\":\"$alpha\"}"
expect "a manifest whose name is not its directory's" 1 "$(
  echo "::error file=$a::name \"gamma\" does not match its directory \"alpha\""
  echo "$refusal"
)" manifests name

good vprefix
write vprefix "$a" "{\"name\":\"alpha\",\"version\":\"v1.0.0\",\"description\":\"$alpha\"}"
expect "a manifest whose version is not a plain triple" 1 "$(
  echo "::error file=$a::version \"v1.0.0\" is not a plain MAJOR.MINOR.PATCH triple"
  echo "$refusal"
)" manifests vprefix

good catalogjson
write catalogjson "$catalog" '{"plugins":['
expect "a catalog that is not JSON" 1 "$(
  echo "::error file=$catalog::not valid JSON"
  echo "$refusal"
)" manifests catalogjson

good nolist
write nolist "$catalog" '{"name":"demo"}'
expect "a catalog with no list of plugins" 1 "$(
  echo "::error file=$catalog::holds no list of plugins"
  echo "$refusal"
)" manifests nolist

good catalogdesc
write catalogdesc "$catalog" "{\"plugins\":[{\"name\":\"alpha\",\"source\":\"./plugins/alpha\",\"description\":\"Alpha does two things.\"},{\"name\":\"beta\",\"source\":\"./plugins/beta\",\"description\":\"$beta\"}]}"
expect "a catalog description that differs" 1 "$(
  echo "::error file=$catalog::the entry \"alpha\"'s description differs from $a's; copy that one here"
  echo "$refusal"
)" manifests catalogdesc

good ghost
write ghost "$catalog" "{\"plugins\":[{\"name\":\"alpha\",\"source\":\"./plugins/alpha\",\"description\":\"$alpha\"},{\"name\":\"beta\",\"source\":\"./plugins/beta\",\"description\":\"$beta\"},{\"name\":\"ghost\",\"source\":\"./plugins/ghost\",\"description\":\"Gone.\"}]}"
expect "a catalog entry with no plugin.json" 1 "$(
  echo "::error file=$catalog::the entry \"ghost\" names ./plugins/ghost, which has no .claude-plugin/plugin.json"
  echo "$refusal"
)" manifests ghost

good readmedesc
write readmedesc README.md "$(printf '%s\n' '# demo' '' '| Plugin | Description |' '|---|---|' \
  "| [\`alpha\`](plugins/alpha) | $alpha |" "| [\`beta\`](plugins/beta) | Six skills do another. |")"
expect "a README row that differs" 1 "$(
  echo "::error file=README.md,line=6::the row for \"beta\" does not carry $b's description; copy that one here"
  echo "$refusal"
)" manifests readmedesc

good readmegone
write readmegone README.md "$(printf '%s\n' '# demo' '' '| Plugin | Description |' '|---|---|' \
  "| [\`beta\`](plugins/beta) | $beta |")"
expect "a plugin the README's table lacks" 1 "$(
  echo "::error file=README.md::the table of plugins has no row for \"alpha\"; add one carrying $a's description"
  echo "$refusal"
)" manifests readmegone

good readmetwice
write readmetwice README.md "$(printf '%s\n' '# demo' '' '| Plugin | Description |' '|---|---|' \
  "| [\`alpha\`](plugins/alpha) | $alpha |" "| [\`beta\`](plugins/beta) | $beta |" "| [\`alpha\`](plugins/alpha) | $alpha |")"
expect "a plugin with two README rows" 1 "$(
  echo "::error file=README.md,line=7::a second row for \"alpha\"; the table holds one per plugin"
  echo "$refusal"
)" manifests readmetwice

[ "$fail" -eq 0 ] || exit 1
echo "test-check-manifests: OK ($n cases: a good repository passes; each bad manifest, catalog and README row is refused with exactly its line, nothing else)"
