#!/usr/bin/env bash
# CI's version-bump gate: every plugin changed since the base commit must
# declare a new version in its .claude-plugin/plugin.json, and a plugin new
# since the base must declare a readable one. Run from the repository root,
# with BASE_SHA set to the full commit SHA to compare against (and FORCED to
# "true" for a forced push); the version-bump job sets both.
#
# Fails closed, by the policy of the platform's admin-plugin gate
# (inno-platform's scripts/admin-plugin-version-bump.mjs and the CI step that
# runs it): this gate exists to fail, so a base it cannot read is not a pass.
# A base the checkout lacks is fetched, retried once. The only skips are a
# first push (no base at all) and a forced push whose old tip is gone from the
# remote (nothing left to compare). Any other failure, a network error, a bad
# SHA or a git diff error, stops the gate with a message.
#
# Every version is read through scripts/plugin-version.sh, so a changed plugin
# with no manifest, or one whose version is not a plain MAJOR.MINOR.PATCH
# string, fails here whether or not it existed at the base. The new version
# must be above the old by scripts/semver.sh's semver_above, field by field as
# numbers, so 1.10.0 beats 1.9.0 (a plain string compare would get that
# backwards); an old version of another shape fails the compare the same as a
# real regression would.
# scripts/test-version-bump.sh runs this gate on a planted repository.
#
# Usage (from the repo root): BASE_SHA=<sha> [FORCED=true] bash scripts/version-bump.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/semver.sh
. "$here/semver.sh"
base="${BASE_SHA:-}"
# A first push to a branch (or an initial commit) reports an all-zero
# "before" SHA with nothing to diff against, so there is nothing to enforce.
if [ -z "$base" ] || [ "$base" = "0000000000000000000000000000000000000000" ]; then
  echo "No base commit to compare against: skipping."
  exit 0
fi
if ! [[ "$base" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]]; then
  echo "::error::the base \"$base\" is not a commit SHA, so the version check did not run"
  exit 1
fi
if ! git rev-parse --verify --quiet --end-of-options "$base^{commit}" >/dev/null; then
  if ! git fetch --no-tags --depth=50 origin "$base" && ! git fetch --no-tags --depth=50 origin "$base"; then
    # The remote listing is captured before it is searched, so a
    # failed ls-remote cannot read as "the base is not listed".
    if [ "${FORCED:-}" = "true" ] && refs="$(git ls-remote origin)" && ! grep -q "^$base" <<<"$refs"; then
      echo "Forced push: the old tip $base is gone from the remote, skipping."
      exit 0
    fi
    echo "::error::could not fetch the base commit $base, so the version check did not run"
    exit 1
  fi
  if ! git rev-parse --verify --quiet --end-of-options "$base^{commit}" >/dev/null; then
    echo "::error::the base $base is not a commit in this checkout, so the version check did not run"
    exit 1
  fi
fi

# scripts/test-version-bump.sh compares this loop's whole output, and
# restates word for word the two refusals and the two OK lines marked
# "Fixture:" below (with the changed-files lines after a refusal). Reword one
# here and update the fixture in the same change, or its test fails.
fail=0
for dir in plugins/*/; do
  plugin="$(basename "$dir")"
  if ! changed="$(git diff --name-only "$base" HEAD -- "$dir")"; then
    echo "::error::git diff against the base $base failed for $plugin, so its version was not checked"
    exit 1
  fi
  [ -n "$changed" ] || continue

  manifest="$dir.claude-plugin/plugin.json"
  # A plain MAJOR.MINOR.PATCH triple, or "" for anything else: no manifest
  # (which the manifests job never visits, since it walks only the manifests
  # that exist), no version, or one of another shape. Either way there is no
  # version to deliver under.
  new="$(bash "$here/plugin-version.sh" "$manifest")" || new=""
  if [ -z "$new" ]; then
    # Fixture: its unreadable().
    echo "::error file=$manifest::\"$plugin\" changed but has no readable .claude-plugin/plugin.json version"
    fail=1
    continue
  fi

  if ! git cat-file -e "$base:$manifest" 2>/dev/null; then
    # Genuinely absent at the base: a new plugin, or one newly
    # versioned for the first time. That absence is itself the
    # bump, so there is nothing to compare against. Fixture: its OK lines.
    echo "OK: $plugin (unversioned) -> $new"
    continue
  fi

  old="$(git show "$base:$manifest" 2>/dev/null | jq -r '.version // ""' 2>/dev/null || echo "")"
  if [ -z "$old" ]; then
    echo "::error file=$manifest::\"$plugin\"'s manifest exists at the base commit ($base) but its version could not be read from it"
    fail=1
    continue
  fi

  if semver_above "$new" "$old"; then
    # Fixture: its OK lines.
    echo "OK: $plugin $old -> $new"
  else
    # Fixture: its not_bumped(), the refusal and its changed-files lines.
    echo "::error file=$manifest::\"$plugin\" changed but its version is still $new: bump it. Delivery is keyed on this value, so users already on $new may never receive these changes."
    echo "  changed files:"
    printf '    %s\n' $changed
    fail=1
  fi
done
[ "$fail" -eq 0 ] || exit 1
