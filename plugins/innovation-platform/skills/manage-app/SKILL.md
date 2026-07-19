---
name: manage-app
description: Use to share, check on, renew, or tear down a live Innovation Platform app via the inno-platform MCP tools (grant_access, revoke_access, app_status, renew_app, decommission_app). Use when the user wants to give someone access, check deploy status, keep an app alive, or delete one.
---

# manage-app

All operations here call tools on the `inno-platform` MCP server (see the
plugin's `.mcp.json`). Every tool authorizes the caller server-side against
the signed-in Okta identity from the MCP OAuth session — **you can only
manage apps you own, unless you are a member of the `inno-platform-admins`
Okta group**. A `forbidden` error back from any of these tools means exactly
that; don't retry it and don't try to work around it locally (there is no
local escalation — authorization lives in the platform, not the client).

## `grant_access({ name, email })` / `revoke_access({ name, email })`

Adds or removes a user from the app's `inno-{name}-users` Okta group — this
group is what the gateway's Cloudflare Access policy checks, so granting
access here is what actually lets someone past the Okta login on
`https://inno-{name}.davidlaporte.org`.

- `email` must look like a real, unquoted email address — the platform
  rejects anything containing quotes, backslashes, or whitespace (this is
  deliberate: it stops an authenticated owner from smuggling Okta
  search-filter syntax through the parameter).
- If the target email has no matching Okta user, the tool returns an error
  rather than silently no-op'ing — surface that to the user rather than
  assuming it worked.
- Authorization: owner of the app, or a platform admin.

## `app_status({ name })`

Read-only. Returns the app's status, owner, URL, creation time, last-seen
time, and last deployment (commit + outcome + timestamp), e.g.:

```
App: my-app
Status: active
Owner: alice@davidlaporte.org
URL: https://inno-my-app.davidlaporte.org
Created: 2026-06-01T12:00:00Z
Last seen: 2026-07-18T09:00:00Z
Last deployment: success (commit a1b2c3d) at 2026-07-17T22:14:00Z
```

Use this to answer "is my app up", "did the last deploy work", or "who owns
this" without needing GitHub Actions access.

## `renew_app({ name })`

Resets the app's idle clock. The platform reclaims resources from apps that
go unused for too long, so if an app is important but seeing low traffic,
call this periodically (or set up a reminder) rather than letting it drift
toward reclamation. This does not redeploy or change anything about the
running app — it only touches the last-seen/idle timestamp.

## `decommission_app({ name })` — destructive, confirm first

Tears the app down: removes the deployed Worker/container, and the
underlying D1 database and R2 bucket data are retained for 30 days before
being purged permanently. **Always confirm with the user by name before
calling this** — there is no MCP-level undo once the 30-day retention window
lapses, and even within the window, restoring is a manual platform-side
operation, not something this tool exposes. Do not call `decommission_app`
speculatively or as part of "cleanup" without the user explicitly naming the
app and confirming they want it gone.

## Authorization summary

| Tool | Who can call it |
|---|---|
| `grant_access` / `revoke_access` | app owner, or `inno-platform-admins` |
| `app_status` | app owner, or `inno-platform-admins` |
| `renew_app` | app owner, or `inno-platform-admins` |
| `decommission_app` | app owner, or `inno-platform-admins` |
| `create_app` | any signed-in Okta user (becomes the owner) |
| `report_issue` | app owner, or `inno-platform-admins` |
| `list_issues` | `inno-platform-admins` only |

`report_issue({ name, summary, logs })` files a diagnostics issue when a
deploy is stuck (see the `ship` skill's failure flow) — it stores the logs for
the platform team and emails them. `list_issues` lets a platform admin review
the open queue for triage.

If you're unsure whether the signed-in user owns an app, call `app_status`
first — its `forbidden` vs. success response is itself the authorization
check.

## Finding app names

If the user doesn't remember an app's exact `name`, call the read-only
`list_apps` tool first — it lists apps the caller owns (or, for platform
admins, all apps), each with its status, owner, and URL.

