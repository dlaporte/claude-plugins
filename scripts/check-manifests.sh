#!/usr/bin/env bash
# CI's manifests job: what a user installs from is well-formed, and each
# plugin's description is one text wherever it is shown.
#   - Every plugins/<name>/.claude-plugin/plugin.json is a JSON object with a
#     name, a version and a description; its name is its directory's; and its
#     version is a plain MAJOR.MINOR.PATCH triple, read through
#     scripts/plugin-version.sh as the version-bump gate reads it (the
#     Innovation Platform compares this value server-side, and answers any
#     other shape "unparseable", as a plugin that reported no version).
#   - The marketplace catalog, .claude-plugin/marketplace.json, is JSON with a
#     list of plugins.
#   - Each catalog entry names a plugin directory that has a plugin.json, and
#     its description is that plugin.json's, compared whole as JSON; so is the
#     description in the plugin's one row of README.md's table of plugins, the
#     row that opens with the plugin's name in backticks as a link. The
#     catalog's description is the one users read at install, and the
#     README's the one they read first; CLAUDE.md says to change the three
#     together. A manifest that cannot give its description is reported
#     above and not compared.
# Prints a ::error line (a GitHub annotation) for each problem, then exits 1
# if there is any. scripts/test-check-manifests.sh runs this on repositories
# it plants.
# Usage (from the repo root): bash scripts/check-manifests.sh
set -euo pipefail
export LC_ALL=C
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$here/lib.sh"
require_jq

catalog=.claude-plugin/marketplace.json
fail=0
nmanifests=0
for manifest in plugins/*/.claude-plugin/plugin.json; do
  [ -e "$manifest" ] || continue
  nmanifests=$((nmanifests + 1))
  plugin="$(basename "$(dirname "$(dirname "$manifest")")")"
  if ! jq empty "$manifest" 2>/dev/null; then
    echo "::error file=$manifest::not valid JSON"
    fail=1
    continue
  fi
  if ! jq -e 'type == "object"' "$manifest" >/dev/null; then
    echo "::error file=$manifest::not a JSON object"
    fail=1
    continue
  fi
  for field in name version description; do
    if [ "$(jq -r --arg f "$field" 'has($f)' "$manifest")" != "true" ]; then
      echo "::error file=$manifest::missing required field \"$field\""
      fail=1
    fi
  done
  name="$(jq -r '.name // ""' "$manifest")"
  if [ "$name" != "$plugin" ]; then
    echo "::error file=$manifest::name \"$name\" does not match its directory \"$plugin\""
    fail=1
  fi
  # Named in the error as JSON, so whitespace in it shows.
  if [ "$(jq -r 'has("version")' "$manifest")" = "true" ] &&
    ! bash "$here/plugin-version.sh" "$manifest" >/dev/null; then
    echo "::error file=$manifest::version $(jq -c '.version' "$manifest") is not a plain MAJOR.MINOR.PATCH triple"
    fail=1
  fi
done

nentries=0
if ! jq empty "$catalog" 2>/dev/null; then
  echo "::error file=$catalog::not valid JSON"
  fail=1
elif ! jq -e '.plugins | type == "array"' "$catalog" >/dev/null; then
  echo "::error file=$catalog::holds no list of plugins"
  fail=1
else
  while IFS=$'\t' read -r name source; do
    nentries=$((nentries + 1))
    manifest="${source#./}/.claude-plugin/plugin.json"
    if [ ! -f "$manifest" ]; then
      echo "::error file=$catalog::the entry \"$name\" names $source, which has no .claude-plugin/plugin.json"
      fail=1
      continue
    fi
    # The manifest loop above has reported one that cannot give this.
    own="$(jq -c '.description | strings' "$manifest" 2>/dev/null)" || own=""
    [ -n "$own" ] || continue
    entry="$(jq -c --arg n "$name" '.plugins[] | select(.name == $n) | .description' "$catalog")"
    if [ "$entry" != "$own" ]; then
      echo "::error file=$catalog::the entry \"$name\"'s description differs from $manifest's; copy that one here"
      fail=1
    fi
    # The README's row: | [`<name>`](<link>) | <description> |
    rows="$(grep_or_none -nF -- "| [\`$name\`](" README.md)"
    if [ -z "$rows" ]; then
      echo "::error file=README.md::the table of plugins has no row for \"$name\"; add one carrying $manifest's description"
      fail=1
      continue
    fi
    first=1
    while IFS= read -r row; do
      line="${row%%:*}"
      if [ "$first" -eq 0 ]; then
        echo "::error file=README.md,line=$line::a second row for \"$name\"; the table holds one per plugin"
        fail=1
        continue
      fi
      first=0
      text="${row#*:}"
      text="${text#*) | }"
      text="${text% |}"
      if [ "$text" != "$(jq -r '.description' "$manifest")" ]; then
        echo "::error file=README.md,line=$line::the row for \"$name\" does not carry $manifest's description; copy that one here"
        fail=1
      fi
    done <<<"$rows"
  done < <(jq -r '.plugins[] | [.name, .source] | @tsv' "$catalog")
fi

if [ "$fail" -ne 0 ]; then
  echo "check-manifests: FAIL, a manifest, the catalog or the README's table above is malformed or disagrees. A plugin's description lives in its plugin.json: the catalog entry and the README row copy it word for word." >&2
  exit 1
fi
echo "check-manifests: OK ($nmanifests plugin manifests; the catalog's $nentries entries and the README's table carry their plugin.json descriptions)"
