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

**Migrating existing code?** If the user already has a repo or codebase they
want on the platform, use the `migrate-app` skill instead — it adds a
read-only assessment (auth to strip, storage to port, gate risks) before
provisioning, then ports the code rather than scaffolding fresh.

## 1. Intake — ask the user for three things

1. **App name** — lowercase letters, digits, hyphens only, 3-29 chars,
   starting with a letter (matches the platform's `isValidAppName` regex:
   `^[a-z][a-z0-9-]{2,28}$`). This becomes the GitHub repo `inno-{name}` and
   the live URL `https://inno-{name}.davidlaporte.org`, so keep it short and
   DNS-safe. A handful of names are reserved by the platform (`platform`,
   `template`, `app`, `replace`).

   **Verify availability before you settle on a name — never recommend or
   confirm a name without checking it first.** Call the **`check_name`** MCP
   tool (read-only; provisions nothing) on the candidate. Only proceed with a
   name it reports as **available**. If it comes back in-use, reserved, or
   invalid, ask the user for a different one; if it's the caller's *own*
   existing app, tell them that (a stopped app is brought back with
   `start_app`, not by re-creating it). `list_apps` shows only the caller's
   own apps, so it can't confirm a name is free platform-wide — use
   `check_name`.
2. **One-line purpose** — becomes the app's `description`.
3. **Initial members' emails** (optional, can be empty) — Okta
   emails to grant access alongside the owner. The list can be added to later
   with the `manage-app` skill's `grant_access`.

Confirm all three back to the user before calling the tool — provisioning is
real (creates a GitHub repo, Okta group, D1 database, R2 bucket) and isn't
cheap to undo.

## 1b. Design the app before provisioning

Provisioning is real and not cheap to undo, and the user deserves to see what
they're approving. Before calling `create_app`, produce and present a real
design — not a one-line summary buried in the tool-approval prompt.

Invoke the **`superpowers:brainstorming`** skill to design the app: what it
does, its data model (D1 tables / R2 objects), its routes/pages, and its access
model (who can see and edit). If that skill isn't available in the session,
run an equivalent inline pass: present the same four points as a short written
design in the conversation and get explicit user approval.

Only once the user has approved the design do you proceed to `create_app`. The
design also seeds the scaffolding in §3.

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
  serving) app URL:
  ```
  App "{name}" created.
  Repo: https://github.com/dlaporte/inno-{name}
  URL: https://inno-{name}.davidlaporte.org (serving once CI deploys it)
  ```
  The app URL is a 404/unprovisioned until the first successful `ship`.

### `create_app` responses — read them, don't assume

`create_app` is idempotent on the name. Branch on what it returns:

- **Created** (text starts with `App "{name}" created.`) — proceed to clone +
  scaffold (below).
- **"You already have an app named …"** — nothing to create. If the response
  says it's **stopped**, the way back is `start_app` (see the `manage-app`
  skill) — starting reattaches the domain with all data intact, no redeploy
  needed.
- **"name isn't available"** / `name_unavailable` — the name belongs to someone
  else; ask for a different one. Do **not** assume it's the user's own app.
- A **purged** app leaves no row behind, so its name simply creates fresh —
  the old data is gone permanently (only the repo and history survived), and
  this is a brand-new app that happens to share the name.

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

**Delete the scaffold marker as you build.** The generated repo ships
`app/.needs-build`, which makes CI skip deployment until it's removed. Once you
begin writing the real app (per the approved design), delete it:

```bash
rm -f app/.needs-build
```

Leaving it in place means `ship` will refuse to deploy — by design.

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
