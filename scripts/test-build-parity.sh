#!/usr/bin/env bash
# Builds one corpus with both browser-interface builders and fails unless they
# write the same thing. The inno-convert-artifact starter's dev/build-ui.mjs
# builds an app's interface locally (npm run dev) the way the platform's CI
# builds it with ci/build-ui.mjs, as a second implementation, so both are run
# here on the same inputs:
#
#   1. takes the platform's ci/build-ui.mjs whose sha256 the pinned record
#      holds (shipped["ci/build-ui.mjs"], platform v0.18.18 on): from the
#      public mirror the platform publishes its CI files to,
#      github.com/dlaporte/inno-platform-ci, the newest of its commits whose
#      ci/build-ui.mjs has that hash, or, given --platform, from that
#      checkout at the record's pinned commit. A file with another hash is
#      never run. Beside it goes scripts/build-parity/cli.mjs in place of the
#      platform's ci/cli.mjs, so nothing else from the platform runs;
#   2. installs the starter's dependencies as scripts/test-starter.sh does
#      (its package.json, with typescript and jsdom at the versions of
#      scripts/starter-test/package-lock.json, from that lock: npm ci,
#      install scripts off). The platform's builder is given that install as
#      its --tools, so both builders run the same esbuild and Tailwind CLI:
#      the versions the record's behavior.buildTools names, which
#      scripts/check-build-tools.sh holds the starter to;
#   3. checks that the two builders list the same entry modules in the same
#      order and the same asset extensions, each inlined as a data URL (the
#      platform's builder exports both; the starter's are read from its
#      source), so a change to either list fails here even when no case
#      below uses the entry or extension that moved;
#   4. for each case under scripts/build-parity/ (its ui/, and an expect file
#      of what its build must hold), builds the case's app/ with the
#      starter's dev/build-ui.mjs (node dev/build-ui.mjs, in app/), then
#      again with the platform's (node ci/build-ui.mjs --tools <install>
#      --app app, beside app/, as CI runs it), and compares the generated
#      modules' four exports (UI_SCRIPT_PATH, UI_STYLES_PATH, UI_SCRIPT and
#      UI_STYLES) line for line, then checks the expect file's lines on the
#      platform's build. The cases are the entry variants (main.tsx with a
#      main.js it must not build, main.ts, main.jsx and main.js), a stylesheet
#      through the Tailwind CLI (both forms of its import) and through
#      esbuild (following its own @import), CSS a module imports, and a PNG,
#      an SVG and a font inlined as data URLs.
#
# The differences each builder's header documents are not compared: the
# generated module's leading comment lines (each names its builder), what
# each prints, and what each does with no ui/, no entry or a failed build
# (CI annotates and exits, the starter throws), which no case here plants.
#
# scripts/test-build-parity-gate.sh proves step 1's gate offline, on records
# and a platform checkout it plants: a record with no sha256 for the builder
# fails closed before any fetch, and a builder with another hash than the
# record's fails before anything is installed or run.
#
# Usage: bash scripts/test-build-parity.sh [--platform <checkout>] [record]
#   (default record scripts/platform-compat.json; a preview's
#   scripts/platform-compat.preview.json, with the checkout it was read
#   from, checks a platform commit before its release)
# Needs git, jq, node and npm, the npm registry and, without --platform,
# github.com. Exits 0 when every case builds alike, 1 when one differs or no
# builder with the pinned hash can be found, and 2 on a bad argument or a
# file it cannot read.
set -euo pipefail
# A hook exports GIT_DIR and GIT_INDEX_FILE, and git honors them over -C, so
# the clone and the reads below would reach the caller's repository: unset
# every GIT_ variable first, as scripts/test-platform-compat.sh does.
for v in "${!GIT_@}"; do unset "$v"; done
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$here/lib.sh"
require_jq
for tool in git node npm; do
  if ! command -v "$tool" >/dev/null; then
    echo "test-build-parity: $tool is required" >&2
    exit 2
  fi
done

platform=""
if [ "${1:-}" = --platform ]; then
  platform="${2:-}"
  if [ -z "$platform" ] || ! git -C "$platform" rev-parse --git-dir >/dev/null 2>&1; then
    echo "test-build-parity: --platform needs a platform checkout" >&2
    exit 2
  fi
  shift 2
fi
record="${1:-$here/platform-compat.json}"
starter="$here/../plugins/innovation-platform/skills/inno-convert-artifact/assets/starter/app"
corpus="$here/build-parity"
mirror="https://github.com/dlaporte/inno-platform-ci.git"
builder_path="ci/build-ui.mjs"

if ! jq -e . "$record" >/dev/null 2>&1; then
  echo "test-build-parity: ${record#"$PWD"/} is not readable JSON" >&2
  exit 2
fi
pin="$(jq -r '.pinned.ref // "an unpinned record"' "$record")"
if ! want="$(jq -er --arg f "$builder_path" '.shipped[$f] | select(type == "string" and test("^[0-9a-f]{64}$"))' "$record" 2>/dev/null)"; then
  echo "test-build-parity: FAIL, ${record#"$PWD"/} ($pin) holds no sha256 for $builder_path under shipped: pin a platform release from v0.18.18 on" >&2
  exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir "$work/ci"
builder="$work/ci/build-ui.mjs"

# 1. The platform's builder with the pinned hash.
if [ -n "$platform" ]; then
  commit="$(jq -r '.pinned.commit // empty' "$record")"
  if [ -z "$commit" ] || ! git -C "$platform" show "$commit:$builder_path" >"$builder" 2>/dev/null; then
    echo "test-build-parity: $platform has no $builder_path at the record's pinned commit (${commit:-none}); fetch it first" >&2
    exit 2
  fi
  from="$platform at $pin (commit $commit)"
else
  git clone --quiet --filter=blob:none --no-checkout "$mirror" "$work/mirror"
  from=""
  for c in $(git -C "$work/mirror" log --format=%H -- "$builder_path"); do
    if [ "$(git -C "$work/mirror" show "$c:$builder_path" | sha256_of)" = "$want" ]; then
      git -C "$work/mirror" show "$c:$builder_path" >"$builder"
      from="the mirror's commit $c"
      break
    fi
  done
  if [ -z "$from" ]; then
    echo "test-build-parity: FAIL, no commit of $mirror holds a $builder_path with the sha256 the record at $pin names ($want). The mirror publishes after the platform's main branch CI runs: run this again once it has, or give --platform <checkout>." >&2
    exit 1
  fi
fi
have="$(sha256_of <"$builder")"
if [ "$have" != "$want" ]; then
  echo "test-build-parity: FAIL, $builder_path from $from has the sha256 $have, and the record at $pin names $want" >&2
  exit 1
fi
cp "$corpus/cli.mjs" "$work/ci/cli.mjs"
echo "test-build-parity: the platform's $builder_path from $from (sha256 $want, the record's at $pin)"

# 2. The starter's dependencies, as scripts/test-starter.sh installs them.
tools="$work/tools"
mkdir "$tools"
jq --slurpfile lock "$here/starter-test/package-lock.json" \
  '.devDependencies.typescript = $lock[0].packages[""].devDependencies.typescript
   | .devDependencies.jsdom = $lock[0].packages[""].devDependencies.jsdom' \
  "$starter/package.json" >"$tools/package.json"
cp "$here/starter-test/package-lock.json" "$tools/package-lock.json"
if ! (cd "$tools" && npm ci --ignore-scripts --no-audit --no-fund --loglevel=error >"$work/npm.log" 2>&1); then
  cat "$work/npm.log" >&2
  echo "test-build-parity: FAIL, npm ci refused the suite's lock. If the starter's package.json moved, run bash scripts/test-starter.sh --relock and commit scripts/starter-test/package-lock.json" >&2
  exit 1
fi

fail=0
# 3. The two builders' entry and asset lists.
lists="$(node --input-type=module - "$builder" "$starter/dev/build-ui.mjs" <<'EOF'
import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";
const [platformBuilder, starterBuilder] = process.argv.slice(2);
const { ENTRIES, ASSET_LOADERS } = await import(pathToFileURL(platformBuilder).href);
const src = readFileSync(starterBuilder, "utf8");
// The first array literal holding the given string, read as JSON.
const list = (s) => {
  const m = src.match(new RegExp(`\\[([^\\[\\]]*"${s.replace(/\./g, "\\.")}"[^\\[\\]]*)\\]`));
  return m ? JSON.parse(`[${m[1]}]`) : null;
};
const loader = /\.map\(\(e\) => \[e, "dataurl"\]\)/.test(src) ? "dataurl" : "another loader";
const out = [];
if (JSON.stringify(list("main.tsx")) !== JSON.stringify(ENTRIES)) {
  out.push(`the entry modules differ: the starter's ${JSON.stringify(list("main.tsx"))}, the platform's ${JSON.stringify(ENTRIES)}`);
}
const theirs = Object.keys(ASSET_LOADERS);
const loaders = new Set(Object.values(ASSET_LOADERS));
if (JSON.stringify(list(".png")) !== JSON.stringify(theirs) || loaders.size !== 1 || !loaders.has(loader)) {
  out.push(`the asset loaders differ: the starter's ${JSON.stringify(list(".png"))} as ${loader}, the platform's ${JSON.stringify(ASSET_LOADERS)}`);
}
console.log(out.join("\n"));
EOF
)"
if [ -n "$lists" ]; then
  printf 'test-build-parity: FAIL, %s\n' "$lists" >&2
  fail=1
else
  echo "test-build-parity: the same entry modules, in the same order, and asset extensions, each inlined as a data URL"
fi

# 4. Each case, built both ways.
# export_line <module> <name>: the generated module's line exporting name.
export_line() { grep_or_none -m1 "^export const $2 = " "$1"; }
cases=0
for dir in "$corpus"/*/; do
  name="$(basename "$dir")"
  cases=$((cases + 1))
  case_dir="$work/cases/$name"
  app="$case_dir/app"
  mkdir -p "$app/dev"
  cp -R "$dir/ui" "$app/ui"
  cp "$starter/dev/build-ui.mjs" "$app/dev/build-ui.mjs"
  ln -s "$tools/node_modules" "$app/node_modules"

  if ! (cd "$app" && node dev/build-ui.mjs) >"$case_dir/starter.log" 2>&1; then
    cat "$case_dir/starter.log" >&2
    echo "test-build-parity: FAIL, $name: the starter's builder failed" >&2
    fail=1
    continue
  fi
  mv "$app/.ui-build/ui.ts" "$case_dir/starter.ts"
  rm -rf "$app/.ui-build" "$app/.dev"
  if ! (cd "$case_dir" && node "$builder" --tools "$tools" --app app) >"$case_dir/platform.log" 2>&1; then
    cat "$case_dir/platform.log" >&2
    echo "test-build-parity: FAIL, $name: the platform's builder failed" >&2
    fail=1
    continue
  fi
  mv "$app/.ui-build/ui.ts" "$case_dir/platform.ts"

  differ=()
  for export in UI_SCRIPT_PATH UI_STYLES_PATH UI_SCRIPT UI_STYLES; do
    line="$(export_line "$case_dir/platform.ts" "$export")"
    if [ -z "$line" ] || [ "$line" != "$(export_line "$case_dir/starter.ts" "$export")" ]; then
      differ+=("$export")
    fi
  done
  # Nothing but comments and the four exports in either module.
  for side in starter platform; do
    if [ -n "$(grep_or_none -v -E -e '^//' -e '^export const UI_(SCRIPT|STYLES)(_PATH)? = ' -e '^$' "$case_dir/$side.ts")" ]; then
      differ+=("the $side's module holds more than the four exports")
    fi
  done
  if [ "${#differ[@]}" -gt 0 ]; then
    echo "test-build-parity: FAIL, $name: the builders wrote different $(join_names "${differ[@]}")" >&2
    fail=1
    continue
  fi

  # The expect file's lines, on the platform's build: <script|styles>
  # has|lacks <text>, or styles empty.
  missed=()
  while read -r what verb text; do
    [ -n "$what" ] || continue
    value="$(export_line "$case_dir/platform.ts" "$( [ "$what" = script ] && echo UI_SCRIPT || echo UI_STYLES)")"
    case "$verb" in
      has) grep -qF -- "$text" <<<"$value" || missed+=("$what has $text") ;;
      lacks) ! grep -qF -- "$text" <<<"$value" || missed+=("$what lacks $text") ;;
      empty) [ "$value" = 'export const UI_STYLES = "";' ] || missed+=("$what empty") ;;
      *) missed+=("an expect line this script cannot read ($what $verb $text)") ;;
    esac
  done <"$dir/expect"
  if [ "${#missed[@]}" -gt 0 ]; then
    printf 'test-build-parity: FAIL, %s: the build does not hold what its expect file says: %s\n' "$name" "$(join_names "${missed[@]}")" >&2
    fail=1
    continue
  fi
  # The platform's own line: the entry it built, and the two sizes.
  built="$(sed -n 's/^Built .* from \(.*\): \(script .*\)\.$/\1, \2/p' "$case_dir/platform.log")"
  echo "test-build-parity: $name: the same script, styles and paths (${built:-the platform printed no Built line})"
done

[ "$fail" -eq 0 ] || exit 1
echo "test-build-parity: OK ($cases cases: the starter's dev/build-ui.mjs and the platform's $builder_path at $pin write the same script, styles and paths, and list the same entries and assets)"
