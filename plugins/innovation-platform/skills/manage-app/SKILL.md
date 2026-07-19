---
name: manage-app
description: Use to share, check on, renew, or tear down a live Innovation Platform app via the inno-platform MCP tools (grant_access, revoke_access, app_status, renew_app, decommission_app). Use when the user wants to give someone access, check deploy status, renew an app that's still in use, or delete one.
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
Status: live
Owner: alice@davidlaporte.org
URL: https://inno-my-app.davidlaporte.org
Created: 2026-06-01T12:00:00Z
Last seen: 2026-07-18T09:00:00Z
Last deployment: live (commit a1b2c3d) at 2026-07-17T22:14:00Z
```

App statuses: `created` (provisioned, not yet deployed), `deploying`, `live`,
`warned`/`stopped` (idle lifecycle), `decommissioned`. Deployment statuses:
`pending`, `deploying`, `live`.

Use this to answer "is my app up", "did the last deploy work", or "who owns
this" without needing GitHub Actions access.

## `renew_app({ name })`

Resets the app's idle clock — **only for an app the user confirms is still in
active use.** This does not redeploy or change anything about the running app;
it only touches the last-seen/idle timestamp.

The platform **deliberately** reclaims resources from apps that go unused. That
idle-reclamation is a cost-control policy, not a malfunction to work around.

**Never offer to schedule or automate renewals** — no cron jobs, reminders,
recurring `renew_app` calls, keep-alive pings, or "I can set that up to run
periodically." Artificially holding an idle app open subverts the reclamation
policy and runs up needless cost, so do not suggest it even if the user seems
worried about losing the app. Present the honest options instead: keep using
it (normal traffic and genuine `renew_app` calls reset the clock naturally),
let it drift to reclamation if it's no longer needed, or `decommission_app` it
deliberately. Keeping a genuinely-idle app running indefinitely is a
platform-policy decision for an admin, not something to engineer around here.

A **decommissioned** app is not renewable — `renew_app` returns
`app_decommissioned`. To bring a decommissioned app back within its retention
window, its **owner** calls `create_app` with the same name (see the `new-app`
skill's restore flow): that recreates its access and reuses its retained data,
and a redeploy (`git push`) brings it online. After the retention window lapses
the data is purged and it can't be restored.

## `decommission_app({ name })` — destructive, confirm first

Tears the app down: removes the deployed Worker/container, and the
underlying D1 database and R2 bucket data are retained for a retention window
(default 30 days) before being purged permanently — along with every record of
the app, at which point the name becomes reusable. **Always confirm with the
user by name before calling this.** Within the retention window the owner can
restore it themselves by calling `create_app` with the same name (see the
`new-app` skill's restore flow); after the window lapses there is no undo. Do
not call `decommission_app` speculatively or as part of "cleanup" without the
user explicitly naming the app and confirming they want it gone.

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

