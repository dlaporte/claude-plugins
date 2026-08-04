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
suffixes: the Innovation Platform parses this value server-side and treats
anything else as "version not reported".

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
