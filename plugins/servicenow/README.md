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
