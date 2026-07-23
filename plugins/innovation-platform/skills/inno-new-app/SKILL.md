---
name: inno-new-app
description: Use when the user wants to create a new app on the Innovation Platform ("new app", "create an app", "start a project on inno-platform"). Guides intake, calls the create_app MCP tool, clones the provisioned repo, and scaffolds app/ per platform-conventions.
---

# inno-new-app

Creates a new Innovation Platform app end to end: intake -> provision via MCP ->
clone -> scaffold. Requires the `inno-platform` MCP server (ships with this
plugin's `.mcp.json`) to be connected. The first call to any `inno-platform`
tool triggers an Okta browser login — that's expected, not an
error; wait for it to complete.

**Migrating existing code?** If the user already has a repo or codebase they
want on the platform, use the `inno-migrate-app` skill instead — it adds a
read-only assessment (auth to strip, storage to port, gate risks) before
provisioning, then ports the code rather than scaffolding fresh.

## 1. Intake — ask the user for three things

1. **App name** — lowercase letters, digits, hyphens only, 3-29 chars,
   starting with a letter. This becomes the repo name `inno-{name}` and the
   app's hostname on the platform domain, so keep it short and DNS-safe.
   (A handful of names are reserved server-side — `check_name` reports
   those, so don't enumerate or guess.)

   **Verify availability before you settle on a name — never recommend or
   confirm a name without checking it first.** Call the **`check_name`** MCP
   tool (read-only; provisions nothing) on the candidate. Only proceed with a
   name it reports as **available**. If it comes back in-use, reserved, or
   invalid, ask the user for a different one; if it's the caller's *own*
   existing app, tell them that (a stopped app is brought back with
   `start_app`, not by re-creating it). `list_apps` shows only the caller's
   own apps, so it can't confirm a name is free platform-wide — use
   `check_name`.

   **Active-app limit.** `check_name` also warns when the user is at their
   active-app limit ("you are at your active-app limit (N of M)") — at the
   cap, `create_app` WILL fail with `app_limit_reached`, so resolve this
   BEFORE any build work: show the user their apps (`list_apps`) and **offer
   to stop one or more** (`stop_app`) to make room — only ever with their
   explicit confirmation, never silently (stopping detaches the app's domain
   and starts its purge countdown). If they decline, stop here: the
   remaining options are asking a platform admin to raise their limit
   (`apps.max_active`, user scope) or not building the app.
2. **One-line purpose** — becomes the app's `description`.
3. **Initial members' emails** (optional, can be empty) — Okta
   emails to grant access alongside the owner. The list can be added to later
   with the `inno-manage-app` skill's `grant_access`.

## 1a. Guardrails check — HARD STOP on conflict

Before confirming anything, call the **`get_guardrails`** MCP tool and
evaluate the proposed **name** and **purpose** against the platform's
acceptable-use policy. This is qualitative judgment (impersonation,
misleading authority, offensive names, prohibited purposes, data handling) —
apply the policy's spirit, not just its examples.

- **Clean** → proceed; no need to mention it unless the user asks.
- **Conflict** → do NOT call `create_app`. Name the specific policy line,
  explain the problem in one plain sentence, and help the user pick a
  compliant name/purpose. If they believe their use is legitimate anyway
  (e.g. sanctioned research), direct them to a platform admin for an explicit
  exception first — you cannot grant one, and you must not create the app
  without it.

Confirm all three back to the user before calling the tool — provisioning is
real (creates a GitHub repo, Okta group, D1 database, R2 bucket) and isn't
cheap to undo.

## 1b. Design the app before provisioning

Provisioning is real and not cheap to undo, and the user deserves to see what
they're approving. Before calling `create_app`, produce and present a real
design — not a one-line summary buried in the tool-approval prompt.

**Fetch the `get_app_contract` MCP tool first** — it carries the platform's
deployment patterns (and, critically, what the platform does NOT support:
background jobs, machine-to-machine APIs, guaranteed long-lived
connections), the stack policy, and the current recommended base images.
Evaluate the user's idea against it before designing; a not-supported
requirement surfaces HERE, not after provisioning.

Invoke the **`superpowers:brainstorming`** skill to design the app: what it
does, its data model (D1 tables / R2 objects), its routes/pages, and its access
model (who can see and edit). If that skill isn't available in the session,
run an equivalent inline pass: present the same points as a short written
design in the conversation and get explicit user approval.

The design includes three contract-informed choices that are **the user's to
make, with your recommendation**:

- **Deployment type** (contract §1 / §1.1): **worker** (a Cloudflare Worker,
  JS/TS, ms cold starts, no Dockerfile) or **container** (a Docker container,
  any stack). **Default to worker for a greenfield app** — most citizen-dev
  ideas are a JS/TS web UI + API, and worker gives instant cold starts and the
  simplest path. Recommend **container** instead when the app needs an
  arbitrary/non-JS stack, native dependencies, ML/data libraries, or
  long-running compute. Decide this FIRST — it gates the stack and scaffold
  choices. Pass it to `create_app` as `type`.
- **Deployment pattern** (from the contract's §5): server-rendered is the
  default recommendation for internal tools; SPA+API when rich client
  interactivity is the point.
- **Stack**: for a **container** app, Python/Starlette is the platform's
  *tested stack* — it should work for most implementations and means starting
  from the template's working reference app; alternative stacks (Node, Go, …)
  are equally supported (HTTP on port 8080, not a language). For a **worker**
  app the stack is JS/TS on the Workers runtime — no separate choice. Recommend
  the tested container stack absent a reason otherwise, and go with what the
  user picks.

Only once the user has approved the design do you proceed to `create_app`. The
design also seeds the scaffolding in §3.

## 2. Call the MCP tool

Call `create_app` on the `inno-platform` MCP server:

```
create_app({ name, description, members, type })
```

`type` is `"worker"` or `"container"` (from the design choice above; omit for
the container default). It cannot be changed after creation — a different type
means a new app.

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
  Repo: https://github.com/{owner}/inno-{name}
  URL: https://inno-{name}.{platform domain} (serving once CI deploys it)
  ```
  **Quote both URLs from the response — never construct them yourself** (the
  GitHub owner and platform domain are deployment-specific). The app URL is
  a 404/unprovisioned until the first successful `inno-ship`.

### `create_app` responses — read them, don't assume

`create_app` is idempotent on the name. Branch on what it returns:

- **Created** (text starts with `App "{name}" created.`) — proceed to clone +
  scaffold (below).
- **"You already have an app named …"** — nothing to create. If the response
  says it's **stopped**, the way back is `start_app` (see the `inno-manage-app`
  skill) — starting reattaches the domain with all data intact, no redeploy
  needed.
- **"name isn't available"** / `name_unavailable` — the name belongs to someone
  else; ask for a different one. Do **not** assume it's the user's own app.
- A **purged** app leaves no row behind, so its name simply creates fresh —
  the old data is gone permanently (only the repo and history survived), and
  this is a brand-new app that happens to share the name.

## 3. Clone and scaffold

```bash
git clone <repo URL from the create_app response>
cd inno-{name}
```

The cloned repo already contains the platform template: the thin
`.github/workflows/deploy.yml` caller workflow (hands-off) and a
**reference implementation** under `app/` + `Dockerfile` (Python/Starlette,
the tested stack). Everything else — `src/gateway/`, `package.json`,
`package-lock.json`, `tsconfig.json`, and `wrangler.jsonc` — is injected by
the platform worker-side at build time and is NOT in the repo; don't create
any of them. Load the `inno-platform-conventions` skill before writing any application
code (stack policy, storage, identity, and the do-not-touch file list).

Scaffold by deployment type:

- **Container app** — load the `inno-containerize` skill before editing the
  Dockerfile.
  - *Tested stack (Python):* start from the reference app and extend it — don't
    regenerate it from scratch.
  - *Another stack:* replace `app/` and the `Dockerfile` wholesale for that
    stack, honoring the contract you fetched in §1b (port 8080, `/healthz`,
    identity headers, the `storage.internal` endpoints, sign-out link).
- **Worker app** — there is **no Dockerfile**. Replace the container reference
  with a Worker entry at **`app/index.ts`** exporting
  `export default { fetch(request, env, ctx) }`, per contract §1.1:
  - a `GET /healthz` route returning 200;
  - identity from `request.headers.get("X-Forwarded-User")` /
    `"X-Forwarded-Groups"` (never build auth);
  - persistence via the injected **bindings** `env.DATA` (D1) and `env.FILES`
    (R2) — *not* `storage.internal` (that's the container path);
  - the platform-wide sign-out link in the UI;
  - any npm deps in **`app/package.json`** (a non-root package.json is allowed);
  - schema via idempotent `CREATE TABLE IF NOT EXISTS` or numbered
    `app/migrations/*.sql` applied on boot (contract §3).

**Delete the scaffold marker as you build.** The generated repo ships
`app/.needs-build`, which makes CI skip deployment until it's removed. Once you
begin writing the real app (per the approved design), delete it:

```bash
rm -f app/.needs-build
```

Leaving it in place means `inno-ship` will refuse to deploy — by design.

Typical scaffolding steps for a new feature (Python reference shown; the
same moves apply in any stack's own idiom):
- Add routes to `app/main.py` (or split into new modules under `app/`,
  importing them from `main.py` — the Starlette `app` object is the ASGI
  entrypoint `uvicorn` runs).
- Add templates under `app/templates/` (never delete the directory while the
  reference Dockerfile is in use — a missing `templates/` dir is a common
  runtime 500, see `inno-containerize`).
- Add pinned dependencies to the stack's manifest (`app/requirements.txt`
  here).

**Rewrite `README.md` — this is required, not optional.** The cloned repo's
README is inno-template's own ("Use this template…", template internals) and
describes nothing about this app. Replace it with a **high-level overview of
the user's app**: what it does, who it's for, and the app's URL. Keep it
short — a few paragraphs is right; the platform mechanics (identity,
storage, CI) already live in `CLAUDE.md` and don't belong here. The README
is the user's file from then on: they can deepen it to whatever level of
detail they prefer, and later features should keep it truthful.

## 4. Hand off

Once scaffolding is in place, tell the user the app was created (repo +
future URL), and that the next steps are: write the app, run `inno-safety-preflight`
locally, then `inno-ship`. Don't push anything yet unless asked — `inno-new-app`'s job
is provisioning + scaffolding, not deploying.
