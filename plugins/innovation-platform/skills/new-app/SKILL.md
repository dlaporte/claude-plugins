---
name: new-app
description: Use when the user wants to create a new app on the Innovation Platform ("new app", "create an app", "start a project on inno-platform"). Guides intake, calls the create_app MCP tool, clones the provisioned repo, and scaffolds app/ per platform-conventions.
---

# new-app

Creates a new Innovation Platform app end to end: intake -> provision via MCP ->
clone -> scaffold. Requires the `inno-platform` MCP server (ships with this
plugin's `.mcp.json`) to be connected. The first call to any `inno-platform`
tool triggers an Okta browser login — that's expected, not an
error; wait for it to complete.

## 1. Intake — ask the user for three things

1. **App name** — lowercase letters, digits, hyphens only, 3-29 chars,
   starting with a letter (matches the platform's `isValidAppName` regex:
   `^[a-z][a-z0-9-]{2,28}$`). This becomes the GitHub repo `inno-{name}` and
   the live URL `https://inno-{name}.davidlaporte.org`, so keep it short and
   DNS-safe. A handful of names are reserved by the platform (e.g. `platform`,
   `admin`, `www`) — if `create_app` rejects the name as invalid or reserved,
   ask for a different one rather than guessing a workaround.
2. **One-line purpose** — becomes the app's `description`.
3. **Initial members' emails** (optional, can be empty) — Okta
   emails to grant access alongside the owner. The list can be added to later
   with the `manage-app` skill's `grant_access`.

Confirm all three back to the user before calling the tool — provisioning is
real (creates a GitHub repo, Okta group, D1 database, R2 bucket) and isn't
cheap to undo.

## 2. Call the MCP tool

Call `create_app` on the `inno-platform` MCP server:

```
create_app({ name, description, members })
```

- The app is created with **owner = the signed-in Okta user** (the caller's
  verified identity from the MCP OAuth session) — you cannot set a different
  owner via this tool, and there is no "create on behalf of" option.
- Provisioning is **synchronous** and takes roughly **15-30 seconds** (GitHub
  repo creation from the `inno-template`, Okta group creation, D1/R2
  resources). Don't assume failure if it takes a few seconds to return — but
  do surface the tool's `error` field verbatim if it comes back non-empty
  (e.g. `invalid_name`, or a wrapped provisioning error) rather than retrying
  blindly.
- On success the tool returns text containing the repo URL and the (not-yet-
  live) app URL:
  ```
  App "{name}" created.
  Repo: https://github.com/dlaporte/inno-{name}
  URL: https://inno-{name}.davidlaporte.org (live once CI deploys it)
  ```
  The app URL is a 404/unprovisioned until the first successful `ship`.

## 3. Clone and scaffold

```bash
git clone https://github.com/dlaporte/inno-{name}.git
cd inno-{name}
```

The cloned repo already contains the platform template: `app/main.py`,
`app/requirements.txt`, `app/templates/index.html`, `Dockerfile`,
`src/gateway/`, `wrangler.jsonc`, `package.json`, `.github/workflows/deploy.yml`.
**Do not regenerate these from scratch** — start from what's there and extend
it. Load the `platform-conventions` skill before writing any application code
(framework, storage, identity, and the do-not-touch file list), and the
`containerize` skill before editing the Dockerfile.

Typical scaffolding steps for a new feature:
- Add routes to `app/main.py` (or split into new modules under `app/`,
  importing them from `main.py` — the Starlette `app` object is the ASGI
  entrypoint `uvicorn` runs).
- Add templates under `app/templates/` (never delete the directory — a
  missing `templates/` dir is a common runtime 500, see `containerize`).
- Add pinned dependencies to `app/requirements.txt`.

## 4. Hand off

Once scaffolding is in place, tell the user the app was created (repo +
future URL), and that the next steps are: write the app, run `preflight`
locally, then `ship`. Don't push anything yet unless asked — `new-app`'s job
is provisioning + scaffolding, not deploying.
