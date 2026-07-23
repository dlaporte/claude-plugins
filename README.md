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

Plugin entries in `marketplace.json` intentionally omit a `version` field
(and each plugin's own `plugin.json` omits it too), so every commit to this
repo is treated as a new version and rolls out to installed users
automatically.
