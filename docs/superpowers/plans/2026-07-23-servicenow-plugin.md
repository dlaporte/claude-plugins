# ServiceNow Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Package the snow-mcp server connection plus six usage skills into a `servicenow` plugin in the personal marketplace, with capability-aware guidance driven by an enhanced `connection_info` tool.

**Architecture:** Two repos. `~/code/snow-mcp` gets a two-field addition to `connection_info` (read_only + tool_packages) so skills can probe the deployment. `~/code/claude-plugins` gets `plugins/servicenow/` mirroring the existing `innovation-platform` plugin: `.claude-plugin/plugin.json` + `.mcp.json` (remote HTTP server) + `skills/` (one core skill with two reference files, five task skills) + a marketplace entry.

**Tech Stack:** Python/FastMCP + respx tests (snow-mcp); JSON manifests + Markdown skills (plugin). Spec: `docs/superpowers/specs/2026-07-23-servicenow-plugin-design.md`.

## Global Constraints

- Plugin name is `servicenow`; skills are `using-snow`, `snow-change`, `snow-order`, `snow-triage`, `snow-report`, `snow-kb` (slash commands group under `snow`).
- Server URL in `.mcp.json` is exactly `https://snow-mcp.davidlaporte.org/mcp`; no auth config in the plugin (server-side per-user OAuth).
- Skills never assume write access: every task skill defers to `using-snow`'s orientation step (connection_info) before promising writes.
- SKILL.md frontmatter: `name` matches its directory; `description` starts "Use when …" (house style).
- snow-mcp commits end with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`; same for claude-plugins.
- snow-mcp work follows TDD (failing test first); manifest/markdown work validates via `python3 -m json.tool` and frontmatter checks.

---

### Task 1: snow-mcp — capability fields on `connection_info`

**Files:**
- Modify: `~/code/snow-mcp/src/snow_mcp/tools/auth_tools.py` (the `connection_info` return dict)
- Test: `~/code/snow-mcp/tests/test_tools_coverage.py` (append; reuses its `call_tool`/`make_server` helpers and `settings` fixture)

**Interfaces:**
- Produces: `connection_info` result gains `"read_only": bool` and `"tool_packages": list[str]` — `["full"]` when full, else sorted requested-∪-core (e.g. `["catalog", "core"]`). Task 3's skill text quotes these field names verbatim.

- [ ] **Step 1: Write the failing tests**

Append to `~/code/snow-mcp/tests/test_tools_coverage.py`:

```python
# ------------------------------------------------- connection_info capabilities


async def test_connection_info_reports_default_capabilities(settings):
    result = await call_tool(settings, "connection_info", {})
    assert result.data["read_only"] is False
    assert result.data["tool_packages"] == ["full"]


async def test_connection_info_reports_read_only_and_scoped_packages():
    scoped = Settings(
        instance_url=INSTANCE,
        client_id="id",
        client_secret="secret",
        base_url="http://localhost:8000",
        read_only=True,
        tool_packages=("core", "catalog"),
    )
    result = await call_tool(scoped, "connection_info", {})
    assert result.data["read_only"] is True
    assert result.data["tool_packages"] == ["catalog", "core"]
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ~/code/snow-mcp && uv run pytest tests/test_tools_coverage.py -q -k connection_info`
Expected: 2 FAILED with `KeyError: 'read_only'`

- [ ] **Step 3: Implement**

In `~/code/snow-mcp/src/snow_mcp/tools/auth_tools.py`, inside `connection_info`, change the return to include the two fields (keep every existing key):

```python
        packages = (
            ["full"]
            if "full" in settings.tool_packages
            else sorted(set(settings.tool_packages) | {"core"})
        )
        return {
            "instance": settings.instance_url,
            "auth": "Per-user OAuth (authorization code + PKCE). All calls run as "
            "the authenticated user under their normal ServiceNow ACLs.",
            "read_only": settings.read_only,
            "tool_packages": packages,
            "notes": [
                "Queries use ServiceNow encoded-query syntax, identical to UI list filters.",
                "Writes trigger business rules just like the UI; client scripts/UI policies do not run.",
                "Access denials (403/empty results) reflect the user's own permissions.",
                "UI-action buttons aren't callable over REST — set underlying fields instead.",
            ]
            + (
                ["Read-only deployment: only read tools are exposed; writes are unavailable."]
                if settings.read_only
                else []
            ),
        }
```

- [ ] **Step 4: Run the full suite**

Run: `cd ~/code/snow-mcp && uv run pytest -q`
Expected: all pass (130 = 128 prior + 2 new)

- [ ] **Step 5: Commit and push (deploys via CI)**

```bash
cd ~/code/snow-mcp
git add src/snow_mcp/tools/auth_tools.py tests/test_tools_coverage.py
git commit -m "Report read_only and tool_packages from connection_info

Lets MCP clients (and the servicenow plugin's skills) probe a
deployment's capabilities explicitly instead of inferring them from
which tools happen to be listed.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git push origin main
gh run watch --exit-status "$(gh run list --branch main --limit 1 --json databaseId --jq '.[0].databaseId')"
```

Expected: push succeeds; Deploy to Cloudflare run concludes `success`.

---

### Task 2: Plugin scaffold + marketplace entry

**Files:**
- Create: `~/code/claude-plugins/plugins/servicenow/.claude-plugin/plugin.json`
- Create: `~/code/claude-plugins/plugins/servicenow/.mcp.json`
- Create: `~/code/claude-plugins/plugins/servicenow/README.md`
- Modify: `~/code/claude-plugins/.claude-plugin/marketplace.json` (append to `plugins` array)

**Interfaces:**
- Produces: plugin id `servicenow` in marketplace `davidlaporte`; MCP server key `servicenow` (tools surface as `mcp__plugin_servicenow_servicenow__<tool>`). Tasks 3–8 drop skills into `plugins/servicenow/skills/`.

- [ ] **Step 1: Write plugin.json**

`~/code/claude-plugins/plugins/servicenow/.claude-plugin/plugin.json`:

```json
{
  "name": "servicenow",
  "description": "Work in ServiceNow as yourself via the snow-mcp server (per-user OAuth): triage incidents and approvals, drive changes through their state model with conflict checks, order from the service catalog, author knowledge, and report on any table. Skills adapt to the deployment's read-only mode and tool packages.",
  "author": {
    "name": "David LaPorte"
  },
  "mcpServers": "./.mcp.json"
}
```

- [ ] **Step 2: Write .mcp.json**

`~/code/claude-plugins/plugins/servicenow/.mcp.json`:

```json
{
  "mcpServers": {
    "servicenow": {
      "type": "http",
      "url": "https://snow-mcp.davidlaporte.org/mcp"
    }
  }
}
```

- [ ] **Step 3: Write README.md**

`~/code/claude-plugins/plugins/servicenow/README.md`:

```markdown
# servicenow

Connects Claude Code to ServiceNow through
[snow-mcp](https://github.com/dlaporte/snow-mcp) — a shared remote MCP server
with **per-user OAuth**: every tool call runs as *you*, under your normal
ServiceNow ACLs. On first use the server walks you through the OAuth flow in
your browser (re-auth later via `/mcp`).

Deployments vary: the server may run read-only (`SNOW_READ_ONLY`) or expose a
subset of tool packages (`SNOW_TOOL_PACKAGES`). The skills probe this with
`connection_info` and frame what they attempt accordingly.

## Skills

| Skill | Use for |
|---|---|
| `using-snow` | Core orientation: capability probe, encoded-query syntax, common tables, attachments, error playbook |
| `snow-triage` | Working your queue: incidents, tasks, SLAs, approvals |
| `snow-change` | Change lifecycle: create, state model, conflicts, scheduling, tasks, risk |
| `snow-order` | Service catalog: find items, fill variables, order, track REQ/RITMs |
| `snow-report` | Read-only reporting: counts, trends, breakdowns on any table |
| `snow-kb` | Knowledge base: search, read, draft, publish |

## Install

From the `davidlaporte` marketplace: `/plugin install servicenow@davidlaporte`
```

- [ ] **Step 4: Add the marketplace entry**

In `~/code/claude-plugins/.claude-plugin/marketplace.json`, append to the `plugins` array (after the `innovation-platform` entry):

```json
    {
      "name": "servicenow",
      "source": "./plugins/servicenow",
      "description": "Work in ServiceNow as yourself via the snow-mcp server: triage incidents and approvals, drive changes through their state model, order from the service catalog, author knowledge, and report on any table — with skills that adapt to read-only deployments.",
      "category": "productivity",
      "homepage": "https://github.com/dlaporte/claude-plugins"
    }
```

- [ ] **Step 5: Validate JSON**

Run:
```bash
python3 -m json.tool ~/code/claude-plugins/.claude-plugin/marketplace.json > /dev/null \
&& python3 -m json.tool ~/code/claude-plugins/plugins/servicenow/.claude-plugin/plugin.json > /dev/null \
&& python3 -m json.tool ~/code/claude-plugins/plugins/servicenow/.mcp.json > /dev/null \
&& echo OK
```
Expected: `OK`

- [ ] **Step 6: Commit**

```bash
cd ~/code/claude-plugins
git add .claude-plugin/marketplace.json plugins/servicenow
git commit -m "Scaffold servicenow plugin: manifests, MCP server, README

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: `using-snow` core skill + references

**Files:**
- Create: `~/code/claude-plugins/plugins/servicenow/skills/using-snow/SKILL.md`
- Create: `~/code/claude-plugins/plugins/servicenow/skills/using-snow/references/encoded-queries.md`
- Create: `~/code/claude-plugins/plugins/servicenow/skills/using-snow/references/common-tables.md`

**Interfaces:**
- Consumes: `connection_info` fields `read_only` / `tool_packages` from Task 1.
- Produces: the orientation contract every task skill references as "Orient first (see using-snow)". Reference file paths quoted by SKILL.md: `references/encoded-queries.md`, `references/common-tables.md`.

- [ ] **Step 1: Write SKILL.md**

`~/code/claude-plugins/plugins/servicenow/skills/using-snow/SKILL.md`:

```markdown
---
name: using-snow
description: Use when doing anything in ServiceNow via the servicenow MCP tools — incidents, changes, catalog orders, knowledge, approvals, record queries. Establishes the capability probe (read-only? which packages?), encoded-query syntax, attachments, and the error playbook. Load this before the first ServiceNow tool call of a session.
---

# Using ServiceNow (snow-mcp)

Every tool call runs **as the authenticated user** under their normal
ServiceNow ACLs — what they can see and change here matches the UI.

## Step 0 — Orient (once per session)

Call `connection_info`, and `whoami` if identity matters. Read two fields:

| Field | How to act on it |
|---|---|
| `read_only: true` | Say so up front. Never attempt or promise creates/updates/orders/state changes — those tools are not registered. Offer the read path instead (queries, reports, lookups). |
| `tool_packages` | Lists what's deployed (`full` = everything). If a package is absent its tools don't exist — don't hunt for them. |

Older servers lack these fields: then infer mode by whether a write tool
(e.g. `create_incident`) appears in the tool list.

**Missing-package fallbacks:** basic reads always work through the generic
table tools — changes via `query_records` on `change_request`, catalog items
via `sc_cat_item`, KB via `kb_knowledge`. What can NOT be emulated without
the package: change state logic/conflicts/scheduling (`change`), ordering
with variables/carts (`catalog`).

## Queries

`query_records` takes ServiceNow encoded-query syntax (same as UI list
filters): clauses joined with `^`, no spaces around `=`, `^OR` for
disjunction, `ORDERBYDESC<field>` for sorting, dot-walking through reference
fields (`caller_id.department=...`), full-text via `123TEXTQUERY321=<terms>`.
Field names come from `describe_table`; results return display values.

For the full operator set (LIKE/IN/BETWEEN, relative-date helpers,
`javascript:` idioms) read `references/encoded-queries.md`.
For which table holds what (task hierarchy, request chain, approvals,
users/groups) read `references/common-tables.md`.

## Attachments (any record)

`list_attachments(table, sys_id)` → pick an attachment →
`get_attachment(attachment_sys_id)` returns text content inline (size-capped;
oversized files return metadata only). `upload_attachment` attaches a file —
pass binary content base64-encoded with `content_is_base64: true`.

## Error playbook

| Symptom | Meaning / next move |
|---|---|
| 401 | Token expired/revoked — user re-authenticates via `/mcp`. |
| 403 or suspiciously empty results | The *user's* ACLs (same as the UI). Not a server bug; say whose permissions ruled. |
| "…is not available on this instance" / "Requested URI does not represent any resource" | That scoped API isn't enabled. Use the table-tool fallback the error names. |
| "Invalid sys_id … not a number like INC0010001" | You passed a record number. Resolve it first: `query_records(table, query="number=INC0010001", limit=1)`. |

## Limits (REST, not this server)

No background scripts; no UI-action buttons (set the underlying fields — the
convenience tools do this); client scripts/UI policies don't run, but
server-side business rules and validation always do.

## Task skills

`snow-triage` (queue/incidents/SLAs/approvals) · `snow-change` (change
lifecycle) · `snow-order` (catalog ordering) · `snow-report` (counts/trends)
· `snow-kb` (knowledge lifecycle).
```

- [ ] **Step 2: Write references/encoded-queries.md**

`~/code/claude-plugins/plugins/servicenow/skills/using-snow/references/encoded-queries.md`:

```markdown
# Encoded-query reference

Syntax: `field<op>value` clauses joined by `^`. No spaces around operators.
`^OR` binds to the previous clause; `^NQ` starts a whole new query (top-level
OR). Sorting is part of the query: `^ORDERBY<field>` / `^ORDERBYDESC<field>`.

## Operators

| Operator | Example | Notes |
|---|---|---|
| `=` `!=` | `state=2` | Choice fields use raw values (see describe_table) |
| `>` `>=` `<` `<=` | `priority<=2` | Also works on dates |
| `IN` / `NOT IN` | `stateIN1,2,3` | Comma-separated |
| `LIKE` / `NOT LIKE` | `short_descriptionLIKEvpn` | Contains |
| `STARTSWITH` / `ENDSWITH` | `numberSTARTSWITHINC` | |
| `ISEMPTY` / `ISNOTEMPTY` | `assigned_toISEMPTY` | |
| `BETWEEN` | `sys_created_onBETWEENjavascript:gs.beginningOfLastMonth()@javascript:gs.endOfLastMonth()` | `@`-separated bounds |
| `123TEXTQUERY321` | `123TEXTQUERY321=email outage` | Full-text across the record |
| `SAMEAS` / `NSAMEAS` | `assigned_toSAMEAScaller_id` | Compare two fields |

## Relative dates (`javascript:` helpers evaluate server-side)

- Today / recent: `sys_created_on>=javascript:gs.beginningOfToday()`,
  `sys_created_on>=javascript:gs.daysAgoStart(7)`
- Calendar spans: `gs.beginningOfLastWeek()`, `gs.beginningOfThisMonth()`,
  `gs.beginningOfLastMonth()`…`gs.endOfLastMonth()`, `gs.beginningOfThisQuarter()`
- Current user: `assigned_to=javascript:gs.getUserID()`

## Dot-walking

Reference fields traverse with `.`: `caller_id.department.name=IT`,
`assignment_group.manager=javascript:gs.getUserID()`,
`cmdb_ci.sys_class_name=cmdb_ci_linux_server`. Works in queries and in
`fields` selections.

## Worked examples

- My group's open incidents, newest first:
  `active=true^assignment_group.nameLIKEservice desk^ORDERBYDESCsys_created_on`
- P1/P2 created this week: `priorityIN1,2^sys_created_on>=javascript:gs.beginningOfThisWeek()`
- Unassigned high-urgency: `assigned_toISEMPTY^urgency=1`
- Changes scheduled over a window:
  `start_date<=2026-08-01 00:00:00^end_date>=2026-07-25 00:00:00`
- RITMs under a request: `request=<sc_request sys_id>` on `sc_req_item`
```

- [ ] **Step 3: Write references/common-tables.md**

`~/code/claude-plugins/plugins/servicenow/skills/using-snow/references/common-tables.md`:

```markdown
# Common tables

Most work records extend `task` — task fields (number, state,
short_description, assigned_to, assignment_group, priority, active,
opened_at) exist on all of them, and `my_work` spans them all.

| Table | Holds | Key fields beyond task |
|---|---|---|
| `incident` | Incidents (INC) | caller_id, category, impact/urgency→priority, close_code/close_notes |
| `change_request` | Changes (CHG) | type, chg_model, risk, start_date/end_date (planned), conflict_status |
| `change_task` | CTASKs under a change | change_request (parent), planned_start_date/planned_end_date |
| `sc_request` | Catalog orders (REQ) | requested_for, stage |
| `sc_req_item` | Items in an order (RITM) | request (parent), cat_item, stage; variables live on the RITM |
| `sc_task` | Fulfillment tasks under a RITM | request_item (parent) |
| `sc_cat_item` | Catalog item *definitions* | name, category, active (read-only browsing; order via catalog tools) |
| `kb_knowledge` | KB articles | kb_knowledge_base, workflow_state (draft/review/published/retired), text |
| `sysapproval_approver` | Approval records | sysapproval (the task), approver, state (requested/approved/rejected) |
| `sys_user` | People | user_name, email, department, manager |
| `sys_user_group` | Groups | name, manager; membership in `sys_user_grmember` |
| `cmdb_ci` | Configuration items (base class) | sys_class_name discriminates subtypes; relations in `cmdb_rel_ci` |
| `sys_journal_field` | Journal entries (comments/work notes) | query `element_id=<record sys_id>`; the Table API doesn't return journals inline |
| `sys_update_set` | Update sets (dev) | state; complete via commit_update_set |

Chain to remember for catalog orders: `sc_request` → `sc_req_item` →
`sc_task`. Chain for changes: `change_request` → `change_task`.
```

- [ ] **Step 4: Validate frontmatter**

Run: `head -4 ~/code/claude-plugins/plugins/servicenow/skills/using-snow/SKILL.md`
Expected: `---`, `name: using-snow`, `description: Use when …` lines present.

- [ ] **Step 5: Commit**

```bash
cd ~/code/claude-plugins
git add plugins/servicenow/skills/using-snow
git commit -m "Add using-snow core skill with query and table references

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: `snow-change` skill

**Files:**
- Create: `~/code/claude-plugins/plugins/servicenow/skills/snow-change/SKILL.md`

**Interfaces:**
- Consumes: `using-snow` orientation contract; change tools (`create_change`, `get_change_states`, `update_change`, `check_change_conflicts`, `get_change_schedule`, `schedule_change_first_available`, `add_change_task`, `assess_change_risk`, `list_standard_change_templates`, `list_change_models`, `get_change`, `list_changes`).

- [ ] **Step 1: Write SKILL.md**

`~/code/claude-plugins/plugins/servicenow/skills/snow-change/SKILL.md`:

```markdown
---
name: snow-change
description: Use when creating, progressing, scheduling, or investigating ServiceNow change requests (CHGs) — change types, the state model, conflict checking, change tasks, risk. Requires the change tool package; read-only deployments can still list/inspect changes, templates, and legal states.
---

# ServiceNow change lifecycle

Orient first (see `using-snow`): `connection_info` tells you if writes are
possible and whether the `change` package is deployed. Without the package,
reads work via `query_records` on `change_request`; state logic, conflicts,
and scheduling do not exist — say so instead of improvising.

## Which change type?

- **Standard** — the work matches a pre-approved template
  (`list_standard_change_templates`). Fastest path; the template supplies
  description/plans (they cannot be overridden). Requires `template=` on
  `create_change`.
- **Normal** — planned work needing assessment/approval. Default.
- **Emergency** — break-fix that can't wait for normal lead time.

On model-driven instances pass `chg_model` (names from `list_change_models`).

## Lifecycle loop

1. `create_change(...)` → note `sys_id`, `number`, and `state`.
2. `get_change_states(sys_id)` → the ONLY reliable source of legal moves.
   State codes vary per instance/model — never hardcode them. Each blocked
   transition lists its unmet conditions (e.g. "No active Change Tasks").
3. `update_change(sys_id, fields={"state": "<value from step 2>"})`.
   Other fields (work_notes, dates, groups) go through the same call.
4. Repeat 2–3 through the model (typically assess → authorize → scheduled →
   implement → review → closed). Approvals gate some moves — the user's
   pending ones show in `list_my_approvals`.

## Scheduling & conflicts (need a CI + planned dates on the change)

- `check_change_conflicts(sys_id)` — collision check against CI schedules,
  maintenance windows, other changes. Trust `has_conflicts`, not raw status.
- `get_change_schedule(sys_id)` — available slots; if it returns a
  `worker_sys_id` the instance is still computing — call again with it.
- `schedule_change_first_available(sys_id)` — book the earliest clear window
  and return the new planned dates.

## Tasks & risk

- `add_change_task(change_sys_id, ...)` creates CTASKs; open CTASKs commonly
  block the move to Review/Closed (get_change_states shows this). Close them
  with `update_record` on `change_task`.
- `assess_change_risk(sys_id)` runs the instance's risk/impact calculation —
  useful before requesting approval.

## Inspecting

`get_change(sys_id)` returns plans + tasks in one call; `list_changes` takes
encoded queries plus `text=` full-text search; resolve a CHG number via
`query_records(change_request, query="number=CHG0031234", limit=1)`.
```

- [ ] **Step 2: Validate frontmatter**

Run: `head -4 ~/code/claude-plugins/plugins/servicenow/skills/snow-change/SKILL.md`
Expected: `name: snow-change` and a `description: Use when …` line.

- [ ] **Step 3: Commit**

```bash
cd ~/code/claude-plugins
git add plugins/servicenow/skills/snow-change
git commit -m "Add snow-change skill: change lifecycle guidance

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: `snow-order` skill

**Files:**
- Create: `~/code/claude-plugins/plugins/servicenow/skills/snow-order/SKILL.md`

**Interfaces:**
- Consumes: `using-snow` orientation contract; catalog tools (`search_catalog`, `list_catalogs`, `get_catalog_item`, `order_catalog_item`, `add_to_cart`, `get_cart`, `update_cart_item`, `remove_cart_item`, `checkout_cart`, `get_order_guide_items`, `checkout_order_guide`, `submit_record_producer`).

- [ ] **Step 1: Write SKILL.md**

`~/code/claude-plugins/plugins/servicenow/skills/snow-order/SKILL.md`:

```markdown
---
name: snow-order
description: Use when finding or ordering anything from the ServiceNow service catalog — hardware/software/access requests, order guides, record-producer forms — or tracking what an order created (REQ/RITM). Requires the catalog tool package; ordering is impossible on read-only deployments.
---

# ServiceNow catalog ordering

Orient first (see `using-snow`). Ordering runs **as the user** — their
entitlements, their cart, their request. On read-only deployments only
`search_catalog` / `list_catalogs` / `get_catalog_item` / `get_cart` exist:
you can find and describe items but must hand the user a portal link to
actually order.

## The flow

1. **Find**: `search_catalog(text=...)`. Too many hits → scope with
   `catalog=`/`category=` (`list_catalogs` browses those). Empty results on a
   small page can be an entitlement artifact (ACLs filter AFTER the page
   limit) — retry with a larger `limit` before concluding it doesn't exist.
2. **Inspect**: `get_catalog_item(sys_id)` → the order form. Collect every
   variable marked `mandatory`; choice variables list their allowed values;
   container variables nest `children`.
3. **Submit** — pick the path by item `type` and situation:
   - Single `catalog_item` → `order_catalog_item(sys_id, variables={...},
     quantity=N)` (order-now).
   - Several items in one order → `add_to_cart` each → `get_cart` to review →
     `checkout_cart` (two-step instances are auto-finalized;
     `finalize=false` stops at the preview).
   - `order_guide` (bundles like onboarding) → `get_order_guide_items(sys_id,
     variables={answers})` to see what it selects → `checkout_order_guide`.
   - `record_producer` ("report an issue"-style forms) →
     `submit_record_producer` — creates the target record directly (often an
     incident), not a REQ.
4. **Track**: ordering returns a REQ number + sys_id. Fulfillment lives on
   RITMs: `query_records(sc_req_item, query="request=<sys_id>")`, and their
   work items on `sc_task` (`request_item=<ritm sys_id>`). The user's own
   RITMs also appear in `my_work`.

## Errors that teach

- "Mandatory Variables are required" → you missed a variable; re-check
  `get_catalog_item`.
- 400 on an item fetch → invalid sys_id OR the user lacks entitlement to the
  item — same message as the portal would give.
- Ordering for someone else: pass `requested_for=<user sys_id>`; the
  instance's request-for policy decides if that's allowed.
```

- [ ] **Step 2: Validate frontmatter**

Run: `head -4 ~/code/claude-plugins/plugins/servicenow/skills/snow-order/SKILL.md`
Expected: `name: snow-order` and a `description: Use when …` line.

- [ ] **Step 3: Commit**

```bash
cd ~/code/claude-plugins
git add plugins/servicenow/skills/snow-order
git commit -m "Add snow-order skill: catalog ordering guidance

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: `snow-triage` skill (incidents + queue + SLAs + approvals)

**Files:**
- Create: `~/code/claude-plugins/plugins/servicenow/skills/snow-triage/SKILL.md`

**Interfaces:**
- Consumes: `using-snow` orientation contract; itsm tools (`my_work`, `get_task_slas`, `create_incident`, `update_incident`, `resolve_incident`, `add_comment`) and approval tools (`list_my_approvals`, `respond_to_approval`).

- [ ] **Step 1: Write SKILL.md**

`~/code/claude-plugins/plugins/servicenow/skills/snow-triage/SKILL.md`:

```markdown
---
name: snow-triage
description: Use when working a ServiceNow queue — reviewing assigned incidents/tasks, checking SLA pressure, updating or resolving incidents, adding comments or work notes, or acting on pending approvals.
---

# ServiceNow triage

Orient first (see `using-snow`). On read-only deployments you can review the
queue and SLAs (`my_work`, `get_task_slas`, `list_my_approvals`) but not
update, resolve, or approve — report findings and stop.

## Work the queue

1. `my_work()` — the user's assigned tasks across every task type
   (incidents, CTASKs, RITMs…). Group by type/priority when summarizing.
2. Prioritize by SLA, not just priority: `get_task_slas(task_sys_id)` shows
   each SLA's stage, percentage consumed, and breach time. Surface anything
   past ~75% first.
3. `list_my_approvals()` — approvals are queue work too. Before deciding,
   fetch the underlying record (`get_record` on the sysapproval target) so
   the user approves with context; then `respond_to_approval(sys_id,
   "approved"|"rejected", comments=...)` — rejections need comments.

## Incident conventions

- **Create**: `create_incident` accepts display names for
  assignment_group/caller (no sys_id hunting); the caller defaults to the
  authenticated user. impact + urgency derive priority — set those two, not
  priority directly.
- **Update vs comment**: field changes via `update_incident`; conversation
  via `add_comment` — `comments` are **customer-visible**, `work_notes` are
  internal. Ask which is intended when the user says "add a note".
- **Resolve**: use `resolve_incident` (not a raw state write) — it sets the
  mandatory close code/notes correctly. Reading past conversation:
  `query_records(sys_journal_field, query="element_id=<sys_id>")`.
```

- [ ] **Step 2: Validate frontmatter**

Run: `head -4 ~/code/claude-plugins/plugins/servicenow/skills/snow-triage/SKILL.md`
Expected: `name: snow-triage` and a `description: Use when …` line.

- [ ] **Step 3: Commit**

```bash
cd ~/code/claude-plugins
git add plugins/servicenow/skills/snow-triage
git commit -m "Add snow-triage skill: queue, SLA, and approvals guidance

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: `snow-report` skill

**Files:**
- Create: `~/code/claude-plugins/plugins/servicenow/skills/snow-report/SKILL.md`

**Interfaces:**
- Consumes: `using-snow` references (`encoded-queries.md`); read tools (`aggregate_stats`, `query_records`, `describe_table`).

- [ ] **Step 1: Write SKILL.md**

`~/code/claude-plugins/plugins/servicenow/skills/snow-report/SKILL.md`:

```markdown
---
name: snow-report
description: Use when answering "how many / which / trend" questions about ServiceNow data — counts by group, breakdowns, top-N lists, date-range trends on incidents, changes, requests, or any table. Fully read-only; works on every deployment.
---

# ServiceNow reporting

Everything here is read-only. Two tools do the work: `aggregate_stats` for
numbers, `query_records` for the rows behind them. Operator syntax:
`using-snow` → `references/encoded-queries.md`. Unfamiliar table? —
`describe_table` first.

## Recipes

- **Count by group** — "open incidents per assignment group":
  `aggregate_stats(table="incident", query="active=true", group_by="assignment_group")`
- **Trend over time** — "incidents opened per week, last month": group by a
  date field and bucket client-side, or run one count per window:
  `aggregate_stats(table="incident", query="sys_created_on>=javascript:gs.beginningOfLastMonth()^sys_created_on<javascript:gs.beginningOfThisMonth()")`
- **Averages/extremes** — `aggregate_stats(..., avg_fields="reassignment_count")`,
  `min_fields`/`max_fields`/`sum_fields` for numeric columns.
- **Top-N list** — newest first, capped:
  `query_records(table="incident", query="active=true^ORDERBYDESCsys_created_on", limit=10, fields=[...])`
  Always pass `fields=` — full records drown the useful columns.
- **Percentage** — run two counts (subset and total) and divide; there is no
  ratio aggregate.

## Habits that keep reports honest

- `query_records` returns `total_matching` — quote it, not the page length.
- Choice fields group by raw value; map labels via `describe_table`'s choice
  lists before presenting.
- Empty result ≠ zero activity: the user's ACLs scope everything (say so
  when a number looks implausibly low).
- Prefer one `aggregate_stats` with `group_by` over N per-group queries.
```

- [ ] **Step 2: Validate frontmatter**

Run: `head -4 ~/code/claude-plugins/plugins/servicenow/skills/snow-report/SKILL.md`
Expected: `name: snow-report` and a `description: Use when …` line.

- [ ] **Step 3: Commit**

```bash
cd ~/code/claude-plugins
git add plugins/servicenow/skills/snow-report
git commit -m "Add snow-report skill: aggregate and query recipes

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: `snow-kb` skill

**Files:**
- Create: `~/code/claude-plugins/plugins/servicenow/skills/snow-kb/SKILL.md`

**Interfaces:**
- Consumes: `using-snow` orientation contract; knowledge tools (`search_knowledge`, `get_article`, `create_article`, `publish_article`).

- [ ] **Step 1: Write SKILL.md**

`~/code/claude-plugins/plugins/servicenow/skills/snow-kb/SKILL.md`:

```markdown
---
name: snow-kb
description: Use when searching, reading, writing, or publishing ServiceNow knowledge-base articles — answering questions from the KB, or turning a resolved issue into a KB article.
---

# ServiceNow knowledge base

Orient first (see `using-snow`). Read-only deployments can search and read
but not author.

## Find & read

- `search_knowledge(query="vpn timeout")` — full-text like the portal search
  box, permission-filtered, relevance-ranked. Falls back to a table search
  automatically if the KB API is off (the `source` field says which
  answered). Structured filters (category, date, author) → `query_records`
  on `kb_knowledge` instead.
- `get_article(sys_id)` — the full body (HTML). Note: like the portal, this
  increments the article's view count.

## Author & publish

1. `create_article(knowledge_base="IT", short_description=..., text=...)` —
   KB by display name; body is HTML (plain text renders as-is). Articles
   start as **drafts**, invisible to readers.
2. Review the draft content with the user before publishing.
3. `publish_article(sys_id)` — then **check the returned state**: KBs with
   an approval workflow route to `review` instead of `published`; tell the
   user which happened.

Contributor/publish rights are per-KB; a 403 means the user lacks them on
that knowledge base (not a tool failure). Good article hygiene: title states
the problem, body leads with the fix, then symptoms/cause.
```

- [ ] **Step 2: Validate frontmatter**

Run: `head -4 ~/code/claude-plugins/plugins/servicenow/skills/snow-kb/SKILL.md`
Expected: `name: snow-kb` and a `description: Use when …` line.

- [ ] **Step 3: Commit**

```bash
cd ~/code/claude-plugins
git add plugins/servicenow/skills/snow-kb
git commit -m "Add snow-kb skill: knowledge lifecycle guidance

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 9: Verification + push

**Files:**
- No new files; verifies Tasks 1–8. Push `~/code/claude-plugins`.

- [ ] **Step 1: Structure + frontmatter sweep**

Run:
```bash
cd ~/code/claude-plugins/plugins/servicenow
ls skills/            # expect: snow-change snow-kb snow-order snow-report snow-triage using-snow
for f in skills/*/SKILL.md; do
  dir=$(basename "$(dirname "$f")")
  grep -q "^name: $dir$" "$f" && grep -q "^description: Use when" "$f" \
    && echo "OK  $dir" || echo "BAD $dir"
done
```
Expected: six `OK` lines, no `BAD`.

- [ ] **Step 2: Confirm live server capability fields**

Run: `curl -s https://snow-mcp.davidlaporte.org/health`
Expected: `{"status":"ok",...}` (Task 1's deploy landed). The
`connection_info` fields themselves get confirmed in Step 4's live session
(the endpoint needs per-user OAuth, so curl can't call it).

- [ ] **Step 3: Push the plugin repo**

```bash
cd ~/code/claude-plugins
git push origin main
```
Expected: push succeeds.

- [ ] **Step 4: User-side install check (needs the human)**

Ask the user to run, in any Claude Code session:
1. `/plugin marketplace update davidlaporte` (or add `~/code/claude-plugins` if not yet added), then install/update `servicenow@davidlaporte` and restart.
2. Confirm the six skills appear in the skill list and `/using-snow` loads.
3. First ServiceNow request triggers the OAuth flow; then `connection_info`
   should show `read_only: true` and `tool_packages: ["full"]` against the
   current production deployment, and the session should frame itself
   read-only.

Expected: all three confirmed; any mismatch loops back to the offending task.
