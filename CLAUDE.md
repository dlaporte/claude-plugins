# Working in this repo

Plugins for Claude Code, published through the `davidlaporte` marketplace.
Everything here is markdown and JSON except one executable asset: the
`inno-convert-artifact` starter
(`plugins/innovation-platform/skills/inno-convert-artifact/assets/starter/app/`),
a Worker in TypeScript, a React interface and two Node scripts, which the
skill copies into an app's own repository. The `starter` CI job builds and
runs it (see "The starter" below); nothing else here is built or run.

## The one rule: change a plugin, bump its version

**Any change under `plugins/<name>/` requires bumping `version` in that
plugin's `.claude-plugin/plugin.json`, in the same commit.** CI enforces this
and will fail the PR otherwise.

This is not bookkeeping. Delivery is keyed on that version: Claude Code caches
an installed plugin at
`~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/` and records the
version in `installed_plugins.json`. Ship edited content under a version a
user already has and they can stay on the old build indefinitely, with nothing
anywhere telling them so, which is exactly the failure that prompted the
version gate in the first place.

So it applies to *every* change that reaches a user, not just interesting
ones. A typo fix in a SKILL.md still needs a patch bump: the user has to
receive the typo fix.

Which component to bump:

- **patch**: wording, clarifications, fixes within existing guidance
- **minor**: a new skill, a new documented workflow, new capability
- **major**: guidance that contradicts a previous version (a retired tool, a
  renamed skill, a changed contract)

Plain `MAJOR.MINOR.PATCH` only. No `v` prefix, no pre-release or build
suffixes: the Innovation Platform parses this value server-side, and its
`Plugin:` line answers anything else with "reported version is not a
MAJOR.MINOR.PATCH triple", which every skill's Version gate treats as a stop.

`.claude-plugin/marketplace.json` entries deliberately carry no version of
their own: `plugin.json` is the single source of truth, and
`claude plugin tag` validates the two agree when both are present. An
entry's `description` is its plugin's `plugin.json` description, word for
word: change both together. The `manifests` CI job fails when they differ.

## Releasing

After merging to `main`:

```
claude plugin tag --push plugins/<name>      # tags <name>--v<version>
```

Users pick it up with:

```
claude plugin marketplace update davidlaporte
claude plugin update <name>@davidlaporte     # restart to apply
```

## The checks

CI's eight jobs (`.github/workflows/ci.yml`) run each check as a step of one
`bash scripts/<name>.sh` line from the repository root, so a check runs
locally as that same line. Each script's header says what it checks, and a
check's `scripts/test-*.sh` twin runs first and proves it on cases it plants.
To run them all before a pull request:

```
grep -E '^ +bash scripts/' .github/workflows/ci.yml | while read -r c; do sh -c "$c" </dev/null || echo "FAILED: $c"; done
```

The version-bump gate skips without `BASE_SHA` (the commit to compare with),
and `test-starter.sh` needs the npm registry. A new check takes the same
shape: a script that sources `scripts/lib.sh` for what the checks share, a
`test-*.sh` twin built on `scripts/test-lib.sh`'s `expect`, and a step of one
line.

## innovation-platform specifics

Every skill opens with the same **Version gate** block: it reads `version`
from `plugin.json` and passes it to the `get_platform_status` MCP tool, which
holds the minimum version the platform accepts and does the comparison
server-side. The block stays whole in each skill, since a skill invoked alone
cannot follow a pointer to its own precondition, and it has one source,
`scripts/version-gate.md`: to change the gate, edit that file and run
`bash scripts/render-gates.sh`, which writes it into every skill. Never edit
a skill's copy. The `version-gate-parity` job runs
`bash scripts/render-gates.sh --check`, which fails when a skill's block
differs from the source, or has no heading, no `Carry on.` line, or two of
either.

Skill content must match what the platform actually does. When in doubt,
prefer having the skill call `get_app_contract` / `get_platform_docs` /
`get_guardrails` at runtime over restating platform behavior here, since
fetched content cannot go stale.

The platform release this plugin is checked against is pinned in
`scripts/platform-compat.json`: the platform's compatibility record
(`docs/compat.json` at a release tag) with the ref and commit it was read at.
`scripts/platform-tools.txt`, the record's tool names, is written by the same
run. CI reads only these copies, never the platform repository: the
`tool-names` job checks every tool name the plugin uses, and the
`platform-compat` job checks that the list is the record's, that every
`sections: [...]` literal under `plugins/innovation-platform/` names a section
the record's contract has, and that the plugin's `version` is at least the
record's app plugin floor (`plugins.app.minVersion`). That job's fixture
tests plant their own records, so a resync leaves them alone. The tool-name
fixture test still reads the real pinned list, so a resync that retires a
tool its fixture uses fails that test until the fixture is edited.

Refresh both files at every resync with the platform:

1. Fetch the release tag into the platform checkout first:
   `git -C <platform checkout> fetch origin tag <release tag>`.
2. Run the script at that tag:
   `bash scripts/platform-compat.sh <platform checkout> <release tag>`
   (v0.16.16 or later; an earlier release has no record). It pins only a
   release tag, `v` and a plain `MAJOR.MINOR.PATCH` triple read from the
   checkout's tags, annotated or lightweight; a branch, a commit SHA or a
   tag of another form is refused. Before it overwrites the previous pin it
   prints what moved since then: served documents, tools' input and output
   schemas, the contract's version and sections, the plugin floors and the
   platform behaviors. That list is the resync's to-do list, and it is
   printed once: save it. Until you commit,
   `git diff scripts/platform-compat.json` shows the same changes.
3. Answer the list in the skills. A renumbered contract needs every skill's
   `sections: [...]` literals updated to the new ids (the contract's history
   says what moved), a new tool needs a skill that names it, and a raised app
   plugin floor needs the plugin bumped to at least that version. An
   `outputRevision` line needs every skill that reads that tool's result
   checked against what the tool now returns (section 7.4.2 of the
   platform's `docs/OPERATIONS.md` says which output changes are breaking).
4. Run the checks ("The checks" above), then commit both files with the
   skill changes that answer the list. When the build tools moved, the
   starter's pins move with them, and its suite's lock must follow ("The
   starter" below).

A committed pin is a release, so nothing merged can still move: the
`platform-compat` job fails a pin whose ref is not a release tag. To check
the plugin against a platform commit before its release, as the platform's
release order does at the release commit, preview it instead:

```
bash scripts/platform-compat.sh --preview <platform checkout> <commit or branch>
```

A preview takes any ref that names a commit, prints what moved since the
committed pin as step 2 does, and writes
`scripts/platform-compat.preview.json` and
`scripts/platform-tools.preview.txt`, which git ignores, leaving the
committed pin as it was. Its list is the release's to-do list; the run at
the tag after the release compares with the same committed pin, so it
prints that list again, with anything that moved after the previewed
commit. The checks read the preview when given its files:

```
bash scripts/check-tool-names.sh --pinned scripts/platform-tools.preview.txt plugins/innovation-platform
bash scripts/check-contract-sections.sh plugins/innovation-platform scripts/platform-compat.preview.json
bash scripts/check-plugin-floor.sh scripts/platform-compat.preview.json
bash scripts/check-build-tools.sh plugins/innovation-platform/skills/inno-convert-artifact/assets/starter/app/package.json scripts/platform-compat.preview.json
```

No file under either plugin, and neither this file, the repository's
`README.md`, the marketplace catalog, the CI workflow under `.github` nor
anything under `scripts/` (whose messages operators read in CI's logs), may
hold an em dash (U+2014) or an en dash (U+2013): write a colon, a semicolon,
a comma or a pair of parentheses instead, as the platform's served documents
do. The `no-dashes` CI job enforces it with `scripts/check-dashes.sh`, which
reads all of them by default. A pattern typed into grep may not match these
characters, so check by bytes with that script; a test that plants one
builds it from its bytes with printf, as `scripts/test-check-dashes.sh`
does.

### The starter

The `inno-convert-artifact` starter is code that ships: the skill copies its
`app/` into the app's repository, and that copy is the app's code from then
on, so a plugin release reaches only the conversions after it. A release
that changes a starter file names the file in the plugin README's history
paragraph, so anyone who converted earlier can copy it again.

`scripts/test-starter.sh` (the `starter` CI job) copies the starter to a
temporary directory, installs its dependencies from
`scripts/starter-test/package-lock.json` with `npm ci`, builds its interface
with its own `dev/build-ui.mjs`, type-checks the Worker and the interface,
and runs `scripts/starter-test/*.test.mjs`: the storage route on workerd
with a local D1, through the starter's own wrangler; the local proxy,
`dev/serve.mjs`; and the built interface in a DOM (jsdom, at the version the
script pins, which it adds beside typescript at run time, never to the
starter's `package.json`). It needs no credential and no network beyond the npm
registry. A change to the starter comes with a test that fails before it:
`bash scripts/test-starter.sh <a copy of the old app/>` runs the suite
against another copy, a starter of innovation-platform 7.4.0 or later only
(the suite reads its `dev/wrangler-config.mjs` and imports `Env` from its
`storage.ts`).

The starter ships no lock of its own (a conversion writes one), so the
suite keeps one. `npm ci` refuses it once the starter's `package.json`
moves; then run `bash scripts/test-starter.sh --relock` and commit the new
lock. The suite's `identity.ts` is a copy of the platform scaffold's, which
the starter imports; its header names the platform release it was copied
at.
