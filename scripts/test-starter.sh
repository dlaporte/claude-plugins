#!/usr/bin/env bash
# The inno-convert-artifact starter's runtime suite. The starter is the one
# executable asset in this repository: its app/ is copied into an app's own
# repository at conversion (the skill's step 6), so a defect in it ships with
# every converted artifact, and a plugin release reaches only the conversions
# after it. This builds the starter and runs it the way a person's
# `npm run dev` does, against a local D1, with no credential and no network
# beyond the npm registry:
#
#   1. copies the starter's app/ to a temporary directory, with the platform
#      scaffold's app/identity.ts beside it (the starter imports it; the copy
#      in scripts/starter-test/ names where it came from);
#   2. installs the starter's dependencies, with typescript added for the type
#      check, from the lock in scripts/starter-test/package-lock.json (npm ci,
#      install scripts off). The starter itself ships no lock: a conversion
#      writes its own (the skill's step 6.7);
#   3. builds the interface with the starter's own dev/build-ui.mjs;
#   4. type-checks the Worker (index.ts, storage.ts, identity.ts and the
#      built module, against the Workers types) and the interface (ui/,
#      against the DOM);
#   5. runs scripts/starter-test/*.test.mjs with node's test runner, one file
#      at a time: the storage route on workerd with a local D1, through the
#      starter's own wrangler, and the local proxy, dev/serve.mjs. A test that
#      holds the skill's guidance to the starter's behavior reads the skill
#      the starter sits in (STARTER_SKILL_DIR, three levels above its app/).
#
# npm ci refuses a lock that no longer matches the starter's package.json, so
# a starter pin that moves (scripts/check-build-tools.sh moves the build
# tools' at a resync) fails here until the lock follows: run this with
# --relock, which writes a new scripts/starter-test/package-lock.json and runs
# nothing else, and commit it.
#
# Usage: bash scripts/test-starter.sh [--relock] [starter app directory]
#   (default plugins/innovation-platform/skills/inno-convert-artifact/assets/starter/app)
# Another starter directory runs the suite against that copy, such as a past
# release's, to show a test failing before its fix.
# Exits 0 when the build, the type check and every test pass.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
suite="$here/starter-test"

# The type checker the suite adds to the starter's devDependencies.
typescript="5.9.3"

relock=0
if [ "${1:-}" = "--relock" ]; then
  relock=1
  shift
fi
starter="${1:-$here/../plugins/innovation-platform/skills/inno-convert-artifact/assets/starter/app}"
for tool in jq node npm; do
  if ! command -v "$tool" >/dev/null; then
    echo "test-starter: $tool is required" >&2
    exit 2
  fi
done
if [ ! -f "$starter/package.json" ]; then
  echo "test-starter: $starter holds no package.json" >&2
  exit 2
fi
skill="$(cd "$starter/../../.." && pwd)"
if [ ! -f "$skill/SKILL.md" ]; then
  echo "test-starter: $starter does not sit in a skill's assets/starter/app/ (no $skill/SKILL.md)" >&2
  exit 2
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
app="$work/app"
cp -R "$starter" "$app"
# Whatever a local run left in the source copy is not the starter's.
rm -rf "$app/node_modules" "$app/.ui-build" "$app/.dev" "$app/.wrangler" "$app/package-lock.json"
cp "$suite/identity.ts" "$app/identity.ts"
jq --arg v "$typescript" '.devDependencies.typescript = $v' "$starter/package.json" >"$app/package.json"
cd "$app"

if [ "$relock" -eq 1 ]; then
  npm install --package-lock-only --ignore-scripts --no-audit --no-fund
  cp package-lock.json "$suite/package-lock.json"
  echo "test-starter: wrote scripts/starter-test/package-lock.json; commit it"
  exit 0
fi

cp "$suite/package-lock.json" package-lock.json
if ! npm ci --ignore-scripts --no-audit --no-fund; then
  echo "test-starter: FAIL, npm ci refused the lock. If the starter's package.json moved, run bash scripts/test-starter.sh --relock and commit scripts/starter-test/package-lock.json" >&2
  exit 1
fi

mkdir suite
for f in "$suite"/*; do
  case "$(basename "$f")" in
    identity.ts | package-lock.json) ;;
    *) cp "$f" suite/ ;;
  esac
done

echo "test-starter: building the interface"
node dev/build-ui.mjs
echo "test-starter: type-checking the Worker and the interface"
npx --no-install tsc -p suite/tsconfig.worker.json
npx --no-install tsc -p suite/tsconfig.ui.json
echo "test-starter: running the suite"
export WRANGLER_SEND_METRICS=false
export STARTER_SKILL_DIR="$skill"
node --test --test-concurrency=1 suite/*.test.mjs
echo "test-starter: OK"
