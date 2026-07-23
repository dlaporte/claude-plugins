# ServiceNow plugin (`servicenow`) — design

**Date:** 2026-07-23
**Repos touched:** `~/code/claude-plugins` (plugin), `~/code/snow-mcp` (one small server change)

## Context

snow-mcp is a shared remote MCP server (per-user OAuth, Streamable HTTP at
`https://snow-mcp.davidlaporte.org/mcp`) exposing 50 ServiceNow tools across
packages (`core`, `itsm`, `approvals`, `knowledge`, `attachments`, `change`,
`catalog`, `dev`). Deployments vary: production currently runs
`SNOW_READ_ONLY=true`, and `SNOW_TOOL_PACKAGES` can scope the toolset. This
plugin packages the server connection together with usage skills so any
Claude Code session gets the MCP *and* knows how to use it well — including
framing its guidance by the deployment's actual capabilities instead of
assuming tools that may not be exposed.

## Plugin structure

Mirrors the existing `innovation-platform` plugin:

```
plugins/servicenow/
├── .claude-plugin/plugin.json      # name "servicenow", author, mcpServers → ./.mcp.json
├── .mcp.json                       # {"mcpServers": {"servicenow": {"type": "http",
│                                   #   "url": "https://snow-mcp.davidlaporte.org/mcp"}}}
├── README.md                       # what it is, install, auth flow, skill index
└── skills/
    ├── using-snow/
    │   ├── SKILL.md
    │   └── references/
    │       ├── encoded-queries.md
    │       └── common-tables.md
    ├── snow-change/SKILL.md
    ├── snow-order/SKILL.md
    ├── snow-triage/SKILL.md
    ├── snow-report/SKILL.md
    └── snow-kb/SKILL.md
```

Plus a `servicenow` entry in `.claude-plugin/marketplace.json`. No OAuth
config in the plugin — the server's own per-user OAuth flow triggers on first
connection.

Naming: plugin `servicenow` (user-facing name; the server is an
implementation detail); skills `using-snow` + `snow-*` so slash commands
group together.

## Server change (snow-mcp): capability reporting

`connection_info` (tools/auth_tools.py) gains two fields:

- `"read_only"`: `settings.read_only`
- `"tool_packages"`: the effective package selection (normalized: requested
  packages ∪ `core`, or `full`)

One test asserting both fields under each mode. Deploys on push via existing
CI. Skills treat `connection_info` as the capability probe; fallback for
older servers: infer mode from whether a write tool (e.g. `create_incident`)
is listed.

## Skills

### `using-snow` (core)

Triggered by any ServiceNow-ish request; the other four point back to it.

- **Step 0 — orient.** Call `connection_info` → instance, `read_only`,
  `tool_packages`; call `whoami` → who you act as. Frame the session:
  read-only ⇒ say so up front, never attempt/promise writes; missing package
  ⇒ its tools don't exist, fall back to generic table tools where possible
  (basic change/catalog reads work via `query_records`; ordering and state
  logic do not).
- **Query essentials** inline (encoded query basics, `123TEXTQUERY321`,
  display values); full operator cheat sheet in
  `references/encoded-queries.md` (LIKE/STARTSWITH, ORDERBY, date operators,
  javascript: helpers, dot-walking); table map in
  `references/common-tables.md` (incident, change_request, change_task,
  sc_request/sc_req_item/sc_task, kb_knowledge, sys_user/sys_user_group,
  sysapproval_approver, task hierarchy).
- **Error playbook:** 401 → re-auth via `/mcp`; 403/empty → the *user's*
  ACLs (matches the UI, not a server bug); "Requested URI does not represent
  any resource" → that scoped API isn't enabled; "Invalid sys_id" → resolve
  number → sys_id first.
- **Attachments** (they apply to any record, so they live here): 
  `list_attachments`/`get_attachment` to read files off a record (size-capped
  content), `upload_attachment` to attach; base64 for binary.
- **Limitations:** no background scripts, no UI-action buttons, no client
  scripts/UI policies (server-side rules still fire).
- **Pointers** to the five task skills.

### `snow-change`

Normal/standard/emergency decision tree (standard ⇒ template required);
lifecycle loop `create_change` → `get_change_states` → `update_change(state=…)`;
conflict check & scheduling prerequisites (CI + planned dates); CTASKs gating
transitions (`add_change_task`, close via `update_record` on change_task);
`assess_change_risk`. Read-only variant: list/get/states/templates/models.

### `snow-order`

`search_catalog` → `get_catalog_item` (mandatory variables, choices,
containers) → pick the submission path: `order_catalog_item` (single item),
cart tools (multi-item), `get_order_guide_items`/`checkout_order_guide`
(bundles), `submit_record_producer` (forms that create records directly).
Track results via `query_records` on `sc_req_item`. Notes: two-step checkout
handled automatically; ACL-after-limit search quirk.

### `snow-triage`

`my_work` queue review → SLA pressure via `get_task_slas` → update
conventions (customer-visible comments vs internal work_notes via
`add_comment`) → `resolve_incident` (close code/notes handled). Escalation
fields (impact/urgency vs priority). Approvals are part of the queue:
`list_my_approvals` → inspect the underlying record → `respond_to_approval`
(works for any approval type; rejection comments required).

### `snow-report`

Read-only reporting recipes: `aggregate_stats` count-by-group, trends via
date-range queries, breakdowns; `query_records` with ORDERBY/limit for
top-N lists. Works on every deployment including read-only.

### `snow-kb`

Knowledge lifecycle: `search_knowledge` (full-text, permission-filtered,
transparent Table API fallback) → `get_article` (full body; increments view
count like the portal) → `create_article` (starts as draft; KB by display
name) → `publish_article` (may land in 'review' if the KB enforces an
approval workflow — check the returned state). Contributor/publish rights
surface as 403s.

## Verification

1. snow-mcp: `uv run pytest` green; push → CI deploy; live
   `connection_info` shows the new fields.
2. Plugin: install/refresh from the local marketplace; confirm the MCP
   server connects, all six skills are listed and invocable by slash name.
3. Read-only framing: against production (read-only) confirm `using-snow`'s
   orientation step reports the mode correctly.

## Out of scope

- A skill for the `dev` package (single admin-gated tool, `commit_update_set`
  — its docstring suffices).
- Any hooks/commands/agents in the plugin — skills only for v1.
- Publishing beyond the personal marketplace.

Coverage note: knowledge gets its own skill (`snow-kb`); approvals fold into
`snow-triage`; attachments fold into `using-snow` — every package except
`dev` has skill coverage.
