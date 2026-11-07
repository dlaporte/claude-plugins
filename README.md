# claude-plugins

David LaPorte's Claude Code plugin marketplace: a monorepo home for plugins
built around the Innovation Platform and other tools.

## Add the marketplace

```
/plugin marketplace add dlaporte/claude-plugins
```

## Install a plugin

```
/plugin install servicenow@davidlaporte
```

`innovation-platform` needs your platform's MCP address. Install it from a terminal with the address set, or copy the exact commands from your platform panel's Connect Claude Code card:

```
claude plugin install innovation-platform@davidlaporte --config platform_url=<your platform's MCP address>
```

Note: the first MCP tool call from an installed plugin opens a browser
window for a login (your organization's identity provider for
`innovation-platform`, ServiceNow OAuth for `servicenow`). That's expected;
every call runs as you.

## Plugins in this marketplace

| Plugin | Description |
|---|---|
| [`innovation-platform`](plugins/innovation-platform) | Build and ship apps on your organization's Innovation Platform: create an app via the inno-platform MCP server as a container (any stack, the default type), a function (its own Cloudflare Worker), or an MCP server for AI assistants (mcp-function / mcp-container) behind the platform's own front door, write it against the platform's application + app-security contracts, run the security gates before shipping through CI/CD, and manage access to a live app. |
| [`servicenow`](plugins/servicenow) | Work in ServiceNow as yourself via the snow-mcp server (per-user OAuth): triage incidents and approvals, drive changes through their state model with conflict checks, order from the service catalog, author knowledge, and report on any table. Skills adapt to the deployment's read-only mode and tool packages. |

## Repo layout

```
.claude-plugin/marketplace.json   the marketplace catalog
plugins/
  innovation-platform/            a plugin, self-contained
    .claude-plugin/plugin.json
    .mcp.json
    skills/…/SKILL.md
  servicenow/                     same shape
scripts/                          CI's checks, the pinned list of the
                                  platform's MCP tool names, and the
                                  inno-convert-artifact starter's runtime
                                  suite (test-starter.sh, starter-test/)
```

## Versioning

Each plugin declares a `version` in its own `plugin.json`, and **any change
under `plugins/<name>/` must bump it in the same commit**: CI fails the PR
otherwise. Why delivery depends on it, and which component to bump, is in
[CLAUDE.md](CLAUDE.md).

## License

MIT: see [LICENSE](LICENSE). Applies to everything in this repo, both
plugins included.
