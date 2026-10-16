# Working in this repo

Plugins for Claude Code, published through the `davidlaporte` marketplace.
Everything here is markdown and JSON — there is no build and no runtime.

## The one rule: change a plugin, bump its version

**Any change under `plugins/<name>/` requires bumping `version` in that
plugin's `.claude-plugin/plugin.json`, in the same commit.** CI enforces this
and will fail the PR otherwise.

This is not bookkeeping. Delivery is keyed on that version: Claude Code caches
an installed plugin at
`~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/` and records the
version in `installed_plugins.json`. Ship edited content under a version a
user already has and they can stay on the old build indefinitely, with nothing
anywhere telling them so — which is exactly the failure that prompted the
version gate in the first place.

So it applies to *every* change that reaches a user, not just interesting
ones. A typo fix in a SKILL.md still needs a patch bump — the user has to
receive the typo fix.

Which component to bump:

- **patch** — wording, clarifications, fixes within existing guidance
- **minor** — a new skill, a new documented workflow, new capability
- **major** — guidance that contradicts a previous version (a retired tool, a
  renamed skill, a changed contract)

Plain `MAJOR.MINOR.PATCH` only. No `v` prefix, no pre-release or build
suffixes: the Innovation Platform parses this value server-side, and its
`Plugin:` line answers anything else with "reported version is not a
MAJOR.MINOR.PATCH triple", which every skill's Version gate treats as a stop.

`.claude-plugin/marketplace.json` entries deliberately carry no version of
their own — `plugin.json` is the single source of truth, and
`claude plugin tag` validates the two agree when both are present.

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

## innovation-platform specifics

Every skill opens with an identical **Version gate** block: it reads
`version` from `plugin.json` and passes it to the `get_platform_status` MCP
tool, which holds the minimum version the platform accepts and does the
comparison server-side. Keep that block byte-identical across all skills — if
you edit one, edit them all.

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
   (v0.16.16 or later; an earlier release has no record). Before it overwrites
   the previous pin it prints what moved since then: served documents, tools'
   input and output schemas, the contract's version and sections, the gateway,
   the plugin floors and the platform behaviors. That list is the resync's
   to-do list, and it is printed once: save it. Until you commit,
   `git diff scripts/platform-compat.json` shows the same changes. Before the
   platform tags a release, its release order runs this script once at the
   release commit instead, as a check, and that pin is never merged. Its
   printed list is the one to keep: the run at the tag compares against the
   files the check left, so it prints only what moved after the release
   commit, which is usually nothing.
3. Answer the list in the skills. A renumbered contract needs every skill's
   `sections: [...]` literals updated to the new ids (the contract's history
   says what moved), a new tool needs a skill that names it, and a raised app
   plugin floor needs the plugin bumped to at least that version. An
   `outputRevision` line needs every skill that reads that tool's result
   checked against what the tool now returns (section 7.4.2 of the
   platform's `docs/OPERATIONS.md` says which output changes are breaking).
4. Run the `platform-compat` and `tool-names` jobs' steps, and the
   `instance-neutral` job's step for the vendored record, locally, then
   commit both files with the skill changes that answer the list.

Never merge a pin that is not at a release tag. A branch commit can still
move before the release, and CI does not check that the pinned ref is a tag.

No file under `plugins/innovation-platform/` may hold an em dash (U+2014) or
an en dash (U+2013): write a colon, a semicolon, a comma or a pair of
parentheses instead, as the platform's served documents do. The `no-dashes`
CI job enforces it with `scripts/check-dashes.sh`. A pattern typed into grep
may not match these characters, so check by bytes with that script.
