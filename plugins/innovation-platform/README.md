# innovation-platform

Claude Code plugin for the davidlaporte.org Innovation Platform. Bundles the
`inno-platform` MCP server and six skills that walk Claude through the whole
app lifecycle: create, write, containerize, gate-check, ship, and manage.

## Install

```
/plugin marketplace add dlaporte/claude-plugins
/plugin install innovation-platform@davidlaporte
```

The first tool call against the `inno-platform` MCP server (e.g. from the
`new-app` skill's `create_app`) opens a browser window for an **Okta login**.
This is expected — the MCP server authenticates you as yourself so every
action it takes (creating an app, granting access, decommissioning) is
attributable to your real Okta identity, not a shared service credential.

## What's in the box

- **`.mcp.json`** — points at `https://inno-platform.davidlaporte.org/mcp`,
  the platform's remote MCP server (tools: `create_app`, `list_apps`,
  `app_status`, `grant_access`, `revoke_access`, `renew_app`,
  `decommission_app`, `get_platform_docs`, `report_issue`, and the
  admin-only `list_issues`).
- **`skills/new-app`** — intake -> `create_app` -> clone -> scaffold.
- **`skills/platform-conventions`** — the approved stack (Starlette, not
  FastAPI), Jinja2 autoescaping, the storage client, identity via
  `X-Forwarded-User`, and the files CI will reject if you touch them.
- **`skills/containerize`** — a copy-pasteable Dockerfile that passes the
  container gate (non-root, port 8080, `/healthz`, patched base image).
- **`skills/preflight`** — run the CI security gates locally before pushing.
- **`skills/ship`** — commit, push to `main`, watch CI, report the live URL.
- **`skills/manage-app`** — grant/revoke access, check status, renew, or
  decommission a live app.

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
