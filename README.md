# claude-plugins

David LaPorte's Claude Code plugin marketplace — a monorepo home for plugins
built around the davidlaporte.org homelab and other tools.

## Add the marketplace

```
/plugin marketplace add dlaporte/claude-plugins
```

## Install a plugin

```
/plugin install innovation-platform@davidlaporte
/plugin install servicenow@davidlaporte
```

Note: the first MCP tool call from an installed plugin opens a browser
window for a login (Okta for `innovation-platform`, ServiceNow OAuth for
`servicenow`) — that's expected; every call runs as you.

## Plugins in this marketplace

| Plugin | Description |
|---|---|
| [`innovation-platform`](plugins/innovation-platform) | Build and ship apps on the davidlaporte.org Innovation Platform. |
| [`servicenow`](plugins/servicenow) | Work in ServiceNow as yourself via the snow-mcp server: triage incidents and approvals, drive changes through their state model, order from the service catalog, author knowledge, and report on any table. Six skills adapt to the deployment's read-only mode and tool packages. |

## Repo layout

```
.claude-plugin/marketplace.json   the marketplace catalog
plugins/
  innovation-platform/            a plugin, self-contained
    .claude-plugin/plugin.json
    .mcp.json
    skills/…/SKILL.md
  servicenow/                     same shape
```

## Versioning

Each plugin declares a `version` in its own `plugin.json`, and **any change
under `plugins/<name>/` must bump it in the same commit** — CI fails the PR
otherwise. See [CLAUDE.md](CLAUDE.md) for which component to bump.

That version is how updates are delivered: Claude Code caches an installed
plugin under `…/cache/<marketplace>/<plugin>/<version>/` and records it in
`installed_plugins.json`, so content shipped under a version a user already
has may never reach them.

Entries in `marketplace.json` carry no version of their own — `plugin.json` is
the single source of truth, and `claude plugin tag` validates that the two
agree whenever both are present.

> Earlier revisions of this repo deliberately omitted the field, on the theory
> that every commit would then roll out automatically. In practice installs
> went stale for weeks unnoticed, and an opaque content hash was all
> `claude plugin list` could show — nothing a user could compare against
> anything. Hence the explicit version, and the CI gate that keeps it honest.

## License

MIT — see [LICENSE](LICENSE). Applies to everything in this repo, both
plugins included.
