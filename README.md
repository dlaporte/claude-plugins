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
```

Note: the first MCP tool call from an installed plugin (e.g.
`innovation-platform`'s `create_app`) opens a browser window for an Okta
login — that's expected.

## Plugins in this marketplace

| Plugin | Description |
|---|---|
| [`innovation-platform`](plugins/innovation-platform) | Build and ship apps on the davidlaporte.org Innovation Platform. |

## Repo layout

```
.claude-plugin/marketplace.json   the marketplace catalog
plugins/
  innovation-platform/            a plugin, self-contained
    .claude-plugin/plugin.json
    .mcp.json
    skills/…/SKILL.md
```

Plugin entries in `marketplace.json` intentionally omit a `version` field
(and each plugin's own `plugin.json` omits it too), so every commit to this
repo is treated as a new version and rolls out to installed users
automatically.
