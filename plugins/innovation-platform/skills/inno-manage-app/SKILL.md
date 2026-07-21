---
name: inno-manage-app
description: Use to share, check on, start, stop, export, open up, or configure a deployed Innovation Platform app via the inno-platform MCP tools (grant_access, revoke_access, set_app_access, app_status, start_app, stop_app, request_start, transfer_app (admin-only), export_app_data, get_app_metrics, set_config). Use when the user wants to give someone access, open an app to everyone with SSO, check deploy status, bring back a stopped app, reassign ownership (admins), download their app's data, or shut one down.
---

# inno-manage-app

All operations here call tools on the `inno-platform` MCP server (see the
plugin's `.mcp.json`). Every tool authorizes the caller server-side against
the signed-in Okta identity from the MCP OAuth session — **you can only
manage apps you own, unless you are a member of the `inno-platform-admins`
Okta group**. A `forbidden` error back from any of these tools means exactly
that; don't retry it and don't try to work around it locally (there is no
local escalation — authorization lives in the platform, not the client).

There is also a web panel at `https://inno-platform.davidlaporte.org` with the
same capabilities (same API, same authorization) — point users there for
anything visual: dashboards, notification history, lifecycle timelines.

## The lifecycle (know this before advising anyone)

States: `created` → `deploying` → `active` ⇄ `warned` → `stopped` → *(purged)*.

- **Any authenticated request to an app resets its idle clock.** Traffic is
  the only keep-alive; there is no "renew" action.
- After 14 idle days (default) an app is **warned** — still fully serving,
  just a notice. 14 days later it is **stopped**: its domain is detached, so
  it can't serve and **can't be deployed** (a `git push` fails with
  `app_stopped` until it's started).
- A stopped app's data is kept for 30 days (default), then **purged**:
  infrastructure, database, and files permanently deleted. The GitHub repo,
  audit history, and notification history survive purge.
- All of these windows are platform config, overridable per app or per user.
  **Unstoppable** apps (admin-set) are exempt from the idle clock entirely.

The platform **deliberately** reclaims resources from idle apps. That is a
cost-control policy, not a malfunction to work around. **Never offer to
schedule or automate keep-alive traffic** — no cron pings, no periodic
anything. If an app should genuinely never expire, that's the admin-set
`lifecycle.unstoppable` config, not an engineering workaround.

## `start_app({ name })` — bring back a stopped app

Reattaches the domain and resets the idle clock; the app serves again
immediately, **no redeploy needed**. Owners have a limited number of
self-service starts (default 1, lifetime, per app — check `app_status`);
admins are unlimited and don't consume the owner's allowance. When the owner
is out of starts, `start_app` returns `start_limit_reached` — use
`request_start({ name, reason })` instead, which notifies every platform
admin and lands in their panel notification feed.

`start_app` can also return **`app_limit_reached`**: starting would put the
owner over their active-app limit (the message carries the numbers). Report
it factually and name the remedies — the owner stops one of their own apps
when THEY choose to, or a platform admin raises their `apps.max_active`
user-scope override. **Do NOT propose or offer to stop specific apps to make
room on a start** — that trade-off (taking down something running) is the
user's to initiate, unprompted.

## `stop_app({ name })` — destructive-ish, confirm first

Detaches the app's domain now: it stops serving, can't be deployed, and its
30-day purge countdown begins. Everything is intact and `start_app` fully
reverses it until the window closes — but **always confirm with the user by
name before calling**, and tell them the purge date from the response.
Rejected with `app_unstoppable` if the app is marked unstoppable (an admin
must turn that off first). There is no un-purge: once the window lapses (or
an admin purges deliberately), only the repo and history remain, and the name
becomes reusable via a fresh `create_app`.

## `grant_access({ name, email })` / `revoke_access({ name, email })`

Adds or removes a user from the app's `inno-{name}-users` Okta group — this
group is what the gateway's Cloudflare Access policy checks, so granting
access here is what actually lets someone past the Okta login on
`https://inno-{name}.davidlaporte.org`.

- `email` must look like a real, unquoted email address — the platform
  rejects anything containing quotes, backslashes, or whitespace.
- If the target email has no matching Okta user, the tool returns an error
  rather than silently no-op'ing — surface that to the user.
- Note: membership grants access to the **app**, not to the platform panel —
  the panel shows people only the apps they own.

## `app_status({ name })` / `get_app_metrics({ name, days })`

Read-only. `app_status` returns status, owner, URL, last-seen time, last
deployment, and — when relevant — the stop/purge deadlines and the owner's
remaining self-service starts. `get_app_metrics` returns per-day requests,
errors, and p50 CPU from Cloudflare analytics.

Deployment statuses: `pending`, `deploying`, `deployed`.

## `set_app_access({ name, open })` — open to everyone, or members-only

Opens an app to **every SSO user, current and future** (open: true) or
returns it to the named member list (open: false). Owner or admin only.

- The named member list is **never modified** — closing always restores
  exactly the configured access. Say so when confirming.
- Takes effect at each user's **next sign-in**; already-signed-in users keep
  their session up to 24h. Set expectations when the user asks "why can they
  still get in?"
- `open_access_disallowed` means an admin has restricted open access for
  this app or owner (`access.allow_open`) — a platform admin can change it
  with `set_config`; do not try to work around it by mass grant_access.
- `open_access_unprovisioned` means the app predates the feature and needs
  the one-time admin backfill (`scripts/backfill-open-access.mjs`).
- Confirm before opening — state plainly that EVERY SSO user will have
  access, not just current members.

## `transfer_app({ name, new_owner_email })` — reassign ownership (ADMINS ONLY)

**Platform admins only** (tightened 2026-07-21): there is no accept step, so
owner-initiated transfers could dump unwanted apps on people. When an app
OWNER asks to transfer their app, do NOT call this tool for them — tell them
a platform admin must do it, and offer to draft the request.

When the caller IS an admin: immediate — the recipient becomes the owner
(lifecycle notices, quota, and management rights move to them) and is added
to the app's access group; the previous owner **keeps access as a regular
member** and is notified. The recipient must be an Okta user.

- Counts against the recipient's `apps.max_active` **unless the app is
  stopped** — an `app_limit_reached` error means the recipient is at their
  cap: an admin can raise their limit. Do NOT offer to stop the recipient's
  apps for them.
- Confirm before calling — this takes effect immediately, there is no
  accept step. State plainly who gains and who keeps what.

## `get_app_usage({ name, days? })` — meters and estimated cost

Collected usage (worker requests/CPU, container vCPU/memory/egress, database
rows and size, file storage/ops) plus a month-to-date cost **estimate**.
Owner or admin. Two honesty rules when relaying results:

- Always say the dollar figure is an **estimate from the platform's Pricing
  settings, not a bill** (the tool's text says so — keep that framing).
- An empty result means "the nightly collector hasn't filled this in yet",
  NOT "the app has no traffic" — live charts are on the app's panel page.

The container is almost always the biggest line; if a user asks how to lower
it, the honest lever is `container.sleep_after` (admin-set, applies on next
deploy).

## `export_app_data({ name })` — take your data with you

Starts a background build of a downloadable archive: the app's D1 database as
a SQL dump, every stored file from its bucket, and a `manifest.json` (app
record, members, effective config). The owner is emailed when it's ready;
the archive appears on the app's panel page (Data exports card) and is kept
for a limited time (default 30 days). Owner or admin only.

- **One export at a time per app** — `export_in_progress` means wait for the
  current one to finish or fail; the platform times out a dead job after 2 h.
- Offer this proactively when a user is about to stop an app they may not
  restart, or asks about leaving/migrating off the platform.
- The platform also builds an archive **automatically before any purge** and
  links it in the purge notice — so "my app was purged, is my data gone?" has
  a real answer: the emailed link keeps working for the retention window.

## Configuration (`get_config` / `set_config` / `remove_config`)

Admin-only, except each user may set their own self-service settings (e.g.
`notify.email.enabled` — their personal email on/off switch) at their own
user scope. Values resolve most-specific-first: **app › user › platform ›
factory default**. Useful keys: `lifecycle.unstoppable` (app or user scope —
user scope covers every app that user owns), `start.self_max`,
`lifecycle.*_days`, `container.sleep_after` (applies on the app's next
deploy), `notify.email.<event>`.

## Notifications (`list_notifications` / `mark_notification_read`)

The platform's durable event feed — lifecycle transitions, deploys, issues.
Owners see their own apps' history (kept even after an app is purged);
admins see everything. Every email the platform sends corresponds to an
entry here.

## Authorization summary

| Tool | Who can call it |
|---|---|
| `grant_access` / `revoke_access` | app owner, or `inno-platform-admins` |
| `app_status` / `get_app_metrics` / `get_app_usage` | app owner, or `inno-platform-admins` |
| `start_app` / `stop_app` / `request_start` | app owner (starts limited), or admins (unlimited) |
| `export_app_data` | app owner, or `inno-platform-admins` |
| `transfer_app` | `inno-platform-admins` only (owners ask an admin) |
| `set_app_access` | app owner, or `inno-platform-admins` (opening gated by `access.allow_open`) |
| `create_app` | any signed-in Okta user (becomes the owner) |
| `report_issue` | app owner, or `inno-platform-admins` |
| `list_issues` / `resolve_issue` / `list_users` / `query_audit` / `get_config` | `inno-platform-admins` only |
| `set_config` / `remove_config` | admins; users for their own self-service settings |
| `list_notifications` / `mark_notification_read` | scoped to the caller |
| `get_platform_status` | any signed-in user |

`report_issue({ name, summary, logs })` files a diagnostics issue when a
deploy is stuck (see the `inno-ship` skill's failure flow) — it stores the logs,
notifies the admins, and shows up in the panel's Issues view for triage.

If you're unsure whether the signed-in user owns an app, call `app_status`
first — its `forbidden` vs. success response is itself the authorization
check.

## Finding app names

If the user doesn't remember an app's exact `name`, call the read-only
`list_apps` tool first — it lists apps the caller owns (or, for platform
admins, all apps), each with its status, owner, and URL.
