# innovation-platform

Claude Code plugin for the davidlaporte.org Innovation Platform. Bundles the
`inno-platform` MCP server and seven skills that walk Claude through the whole
app lifecycle: create (or migrate existing code), write, containerize,
gate-check, ship, and manage.

## Install

```
/plugin marketplace add dlaporte/claude-plugins
/plugin install innovation-platform@davidlaporte
```

The first tool call against the `inno-platform` MCP server (e.g. from the
`new-app` skill's `create_app`) opens a browser window for an **Okta login**.
This is expected — the MCP server authenticates you as yourself so every
action it takes (creating an app, granting access, stopping or starting one)
is attributable to your real Okta identity, not a shared service credential.

## What's in the box

- **`.mcp.json`** — points at `https://inno-platform.davidlaporte.org/mcp`,
  the platform's remote MCP server (tools: `create_app`, `check_name`,
  `list_apps`, `app_status`, `grant_access`, `revoke_access`, `set_app_access`, `stop_app`,
  `start_app`, `request_start`, `transfer_app`, `export_app_data`, `get_app_metrics`, `get_app_usage`, `get_platform_status`,
  `list_notifications`, `mark_notification_read`, `mark_all_notifications_read`,
  `get_platform_docs`, `get_guardrails`, `get_ci_status`, `report_issue`,
  self-service `set_config`/`remove_config`, and the admin-only `purge_app`,
  `get_config`, `list_issues`, `resolve_issue`, `list_users`, `query_audit`).
  There's also a
  web panel with the same capabilities at
  `https://inno-platform.davidlaporte.org`.
- **`skills/inno-new-app`** — intake -> `create_app` -> clone -> scaffold.
- **`skills/inno-migrate-app`** — assess an existing repo (read-only), then
  provision and port it into a new `inno-{app}`, keeping its stack where
  the gates allow.
- **`skills/inno-platform-conventions`** — the approved stack (Starlette, not
  FastAPI), Jinja2 autoescaping, the storage client, identity via
  `X-Forwarded-User`, and the files CI will reject if you touch them.
- **`skills/inno-containerize`** — a copy-pasteable Dockerfile that passes the
  container gate (non-root, `EXPOSE 8080`, patched base image; `/healthz` is a runtime contract the gateway relies on — CI does not probe it).
- **`skills/inno-safety-preflight`** — run the CI security gates locally before pushing.
- **`skills/inno-ship`** — commit, push to `main`, watch CI, report the live URL.
- **`skills/inno-manage-app`** — grant/revoke access, check status and metrics,
  stop or start an app, and read its notifications. Idle apps are warned,
  stopped, then purged on a config-driven clock; any traffic resets it.

## How the platform enforces security

The plugin's skills *guide* you toward compliant code, but nothing here is
trusted — enforcement happens server-side. Every push to `main` in an
`inno-{app}` repo runs the platform's reusable CI workflow, which an app
author cannot edit or bypass (only the thin caller `deploy.yml` in their own
repo is editable, and stripping it just means the reusable workflow never
runs). That workflow gates the deploy behind config-integrity, secret
scanning, SAST, dependency auditing, and container/image scanning — all of
which must pass before a deploy token is even requested. At deploy time, the
platform's broker independently verifies the GitHub OIDC token's signed
`job_workflow_ref` claim to confirm the run actually executed the platform's
exact reusable workflow from `main` before minting a narrowly-scoped
Cloudflare deploy token; a forked or gate-stripped workflow gets a `403
deploy_denied` and never reaches Cloudflare. In short: skills guide, CI
validates, and the deploy broker enforces provenance — so only code that
went through the platform's own CI can ever end up live at
`https://inno-{app}.davidlaporte.org`.
