# innovation-platform

Claude Code plugin for the davidlaporte.org Innovation Platform. Bundles the
`inno-platform` MCP server and seven skills that walk Claude through the whole
app lifecycle: create (or migrate existing code), write, containerize,
gate-check, ship, and manage. Apps deploy as one of two **types** behind the
same identity gateway — a **worker** (its own Cloudflare Worker, JS/TS, the
default for greenfield apps) or a **container** (any stack, a Dockerfile) —
chosen at `register_app`.

**Repos are user-owned.** An app is created by **registering a GitHub repo you
own**. You create a repo from the public `inno-template` ("Use this template" →
your own account or org, so it lands already scaffolded in your ownership),
install the platform's GitHub App on it, and the `register_app` MCP tool
provisions the app's resources and binds them to your repo. `register_app` is a
two-step call: the first returns the App install link (and points at the
template for creating the repo); after you install the App, the second call
finishes and returns your `deploy.yml`. There is no platform-owned repo — the
repo is yours (any account, public or private), and uninstalling the App unlinks
and stops the app. (The old `create_app` tool has been retired.)

## Install

```
/plugin marketplace add dlaporte/claude-plugins
/plugin install innovation-platform@davidlaporte
```

The first tool call against the `inno-platform` MCP server (e.g. from the
`inno-new-app` skill's `register_app`) opens a browser window for an **Okta
login**.
This is expected — the MCP server authenticates you as yourself so every
action it takes (creating an app, granting access, stopping or starting one)
is attributable to your real Okta identity, not a shared service credential.

## What's in the box

- **`.mcp.json`** — points at `https://inno-platform.davidlaporte.org/mcp`,
  the platform's remote MCP server (tools: `register_app`, `check_name`,
  `list_apps`, `app_status`, `grant_access`, `revoke_access`, `set_app_access`, `stop_app`,
  `start_app`, `request_start`, `transfer_app`, `export_app_data`, `get_app_metrics`, `get_app_usage`, `get_app_logs`, `restart_app`, `get_platform_status`,
  `list_notifications`, `mark_notification_read`, `mark_all_notifications_read`,
  `get_platform_docs`, `get_guardrails`, `get_app_contract`, `get_app_security`, `get_ci_status`, `report_issue`,
  self-service `set_config`/`remove_config`, and the admin-only `purge_app`,
  `get_config`, `list_issues`, `resolve_issue`, `list_users`, `query_audit`).
  There's also a
  web panel with the same capabilities at
  `https://inno-platform.davidlaporte.org`.
- **`skills/inno-new-app`** — intake -> create a repo from `inno-template` +
  install the GitHub App -> `register_app` -> clone -> scaffold.
- **`skills/inno-migrate-app`** — assess an existing repo (read-only), then
  register and adapt it **in place**, keeping its stack where the gates allow.
- **`skills/inno-platform-conventions`** — stack policy (Python/Starlette is
  the tested stack; any stack meeting the contract is fine), escaping,
  the storage client/endpoints, identity via `X-Forwarded-User`, and the
  files CI will reject if you touch them. Requirements are served live by
  the `get_app_contract` tool — skills cite it, not stale copies.
- **`skills/inno-containerize`** — **container-type apps only:** the container
  contract for ANY stack (non-root, `EXPOSE 8080`, patched base, CVE-clean)
  with Python/Node/Go recipes; base images digest-pinned from
  `get_app_contract`. Worker-type apps have no Dockerfile and skip this.
- **`skills/inno-safety-preflight`** — run the CI security gates, plus a
  guardrails, application-contract, and `get_app_security` (app-code
  authorization/IDOR) review, before pushing.
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
