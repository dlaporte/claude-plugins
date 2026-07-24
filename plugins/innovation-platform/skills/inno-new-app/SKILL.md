---
name: inno-new-app
description: Use when the user wants to create a new app on the Innovation Platform ("new app", "create an app", "start a project on inno-platform"). Guides intake, has the user create a repo from the inno-template and install the platform GitHub App, calls register_app to provision + bind it, then scaffolds app/ per platform-conventions.
---

# inno-new-app

Creates a new Innovation Platform app end to end: intake -> the user creates a
repo **they own** from the platform template -> install the platform GitHub App
-> `register_app` provisions + binds it -> clone + scaffold. Requires the
`inno-platform` MCP server (ships with this plugin's `.mcp.json`) to be
connected. The first call to any `inno-platform` tool triggers an Okta browser
login — that's expected, not an error; wait for it to complete.

**The repo is the USER's.** There is no platform-owned repo model anymore. The
user creates a GitHub repo in **their own** account or org from the public
`inno-template`, installs the platform's GitHub App on it, and `register_app`
finishes the job. The old `create_app` tool no longer exists, and the platform
never creates a `dlaporte/inno-{name}` repo on the user's behalf.

**Already have an existing repo?** If the user wants to put a repo/codebase they
*already* have on the platform (not create a fresh one from the template), use
the `inno-migrate-app` skill instead — it registers the existing repo in place
and adapts it to the contract, no scaffolding-from-template.

## 1. Intake — ask the user for four things

1. **App name** — lowercase letters, digits, hyphens only, 3-29 chars,
   starting with a letter. This drives the app's **hostname** on the platform
   domain (`inno-{name}.<domain>`), so keep it short and DNS-safe. It is NOT
   the repo name — the repo name is the user's choice (see below). A handful of
   names are reserved server-side — `check_name` reports those, so don't
   enumerate or guess.

   **Verify availability before you settle on a name — never recommend or
   confirm a name without checking it first.** Call the **`check_name`** MCP
   tool (read-only; provisions nothing) on the candidate. Only proceed with a
   name it reports as **available**. If it comes back in-use, reserved, or
   invalid, ask the user for a different one; if it's the caller's *own*
   existing app, tell them that (a stopped app is brought back with
   `start_app`, not by re-registering it). `list_apps` shows only the caller's
   own apps, so it can't confirm a name is free platform-wide — use
   `check_name`.

   **Active-app limit.** `check_name` also warns when the user is at their
   active-app limit ("you are at your active-app limit (N of M)") — at the cap,
   `register_app` WILL fail with `app_limit_reached`, so resolve this BEFORE any
   build work: show the user their apps (`list_apps`) and **offer to stop one or
   more** (`stop_app`) to make room — only ever with their explicit
   confirmation, never silently (stopping detaches the app's domain and starts
   its purge countdown). If they decline, stop here: the remaining options are
   asking a platform admin to raise their limit (`apps.max_active`, user scope)
   or not building the app.
2. **Repo** — the `owner/repo` slug of the GitHub repo the user will create
   from the template (§2). The **owner is the user's** account or org, and the
   repo name is **their choice** — suggest `inno-{name}` for familiarity, but it
   is not required and can be anything. The repo may be public or private.
3. **One-line purpose** — becomes the app's `description`.
4. **Initial members' emails** (optional, can be empty) — Okta emails to grant
   access alongside the owner. The list can be added to later with the
   `inno-manage-app` skill's `grant_access`.

## 1a. Guardrails check — HARD STOP on conflict

Before confirming anything, call the **`get_guardrails`** MCP tool and evaluate
the proposed **name** and **purpose** against the platform's acceptable-use
policy. This is qualitative judgment (impersonation, misleading authority,
offensive names, prohibited purposes, data handling) — apply the policy's
spirit, not just its examples. `register_app` requires you to pass
`accept_guardrails: true`, which asserts the app will follow these guardrails —
do not pass it until you've actually done this review.

- **Clean** → proceed; no need to mention it unless the user asks.
- **Conflict** → do NOT call `register_app`. Name the specific policy line,
  explain the problem in one plain sentence, and help the user pick a compliant
  name/purpose. If they believe their use is legitimate anyway (e.g. sanctioned
  research), direct them to a platform admin for an explicit exception first —
  you cannot grant one, and you must not register the app without it.

Confirm the name, repo, purpose, and members back to the user before going
further — registration provisions real resources (Okta group, D1 database, R2
bucket) and binds them to the user's repo.

## 1b. Design the app before registering

The user deserves to see what they're approving. Before registering, produce and
present a real design — not a one-line summary buried in a tool-approval prompt.

**Fetch the `get_app_contract` MCP tool first** — it carries the two deployment
**types** and their requirement deltas (§1.1), the deployment patterns (and what
the platform does NOT support: background jobs, machine-to-machine APIs,
guaranteed long-lived connections), the stack policy, and the current
recommended base images. Evaluate the user's idea against it before designing; a
not-supported requirement surfaces HERE, not after registration.

Invoke the **`superpowers:brainstorming`** skill to design the app: what it does,
its data model (D1 tables / R2 objects), its routes/pages, and its access model
(who can see and edit). If that skill isn't available in the session, run an
equivalent inline pass: present the same points as a short written design in the
conversation and get explicit user approval.

The design includes three contract-informed choices that are **the user's to
make, with your recommendation**:

- **Deployment type** — `worker` or `container` (passed to `register_app`;
  default container server-side, but for a **greenfield** app you recommend and
  default to **`worker`**):
  - **`worker` (recommend for greenfield):** the app is its own Cloudflare
    Worker (JS/TS) behind the gateway — ms cold starts, no Dockerfile,
    Workers-native bindings. This is the right fit for the common citizen-dev
    shape (a small web UI + JSON API in TS/JS).
  - **`container`:** choose this when the description gives a **clear signal**
    for it — an explicit **non-TS/JS stack** (Python, Go, Ruby, …), **native
    dependencies** or system binaries, **long-running / heavy compute**, or a
    port of existing non-JS code (that's `inno-migrate-app`, which defaults to
    container). Absent such a signal, prefer worker.
  - State your recommendation and the reason, and go with the user's call.
- **Deployment pattern** (contract §5): server-rendered is the default for
  internal tools; SPA+API when rich client interactivity is the point — applies
  to either type.
- **Stack** — follows from the type: a **worker** app is TS/JS (that is what
  Workers run). A **container** app defaults to Python/Starlette (the tested
  container stack, with a working reference app), or the user's chosen stack —
  any language is supported; the container contract is HTTP on port 8080, not a
  language.

Only once the user has approved the design do you proceed. The type and design
seed the scaffolding in §4.

## 2. Have the user create the repo from the template

The user creates the repo — you cannot do it for them (the platform has no
create-on-behalf path, and the repo must land in the user's own ownership).
Walk them through it in plain steps:

1. Open **`https://github.com/dlaporte/inno-template/generate`** — GitHub's
   "Use this template" page for the public `inno-template`. (You can also reach
   it from the template repo's green **"Use this template" → "Create a new
   repository"** button.)
2. Set the **owner** to their own account or org, and the **repository name** to
   their choice (suggest `inno-{name}`). Public or private is fine.
3. Click **Create repository**. The repo lands in **their** ownership, already
   scaffolded from the template.

Note the resulting `owner/repo` slug — that's the `repo` argument for
`register_app`.

## 3. Register the app (two calls)

`register_app` is a **two-step** flow with an App install in between. Call it,
give the user the link it returns, wait for them to install, then call it again.

### Call 1 — start registration, get the install link

```
register_app({ name, repo, description, type, members, accept_guardrails: true })
```

- `name` — the app name from §1 (drives the hostname).
- `repo` — the `owner/repo` slug from §2 (a **slug, not a URL**).
- `type` — from the design decision (§1b): `"worker"` for the greenfield
  default, `"container"` when the description warranted it. Omit for container.
  The type is fixed at registration and can't be switched later (register a new
  app to change it).
- `accept_guardrails: true` — required; you must have done the §1a review.
- `members` — optional list of Okta emails.

The first call returns text beginning **`Registration started for "{name}" ←
{repo}.`** It includes (a) the template link again in case the repo doesn't
exist yet, and (b) an **App install link** (`https://github.com/apps/…/installations/new?state=…`).
**Give the user the install link verbatim** and ask them to:

1. Open it, and **install the platform GitHub App** on the account/org that owns
   `repo`, granting it access to that repository (repo-only access is fine — they
   can scope it to just this repo).
2. Save the configuration; GitHub redirects them to the platform's verification
   page confirming the repo is verified.

The link expires in 24 hours.

### Call 2 — finish provisioning, get the deploy.yml

Once the user confirms they've installed the App, call `register_app` **again
with the same arguments**. This finishes the job server-side (prunes the
template scaffold to the chosen type via the installation token, provisions the
Okta group + D1 + R2, and binds the repo). It returns text beginning **`App
"{name}" registered from {repo}`** and containing:

- `URL (after first deploy): https://inno-{name}.<platform domain>` — **quote
  this from the response, never construct it** (the platform domain is
  deployment-specific). The URL 404s until the first successful `inno-ship`.
- A `.github/workflows/deploy.yml` — the thin caller workflow that wires the
  repo to the platform's reusable CI. The template already ships a `deploy.yml`;
  make sure the one in the repo **matches what `register_app` returned** (in
  particular its `with: app: {name}` input and the
  `dlaporte/inno-platform-ci/.github/workflows/platform-ci.yml@main` reference)
  — write/adjust it from the response if needed. Keep its `workflow_dispatch`
  trigger (the platform re-dispatches it for security respins).

### Reading register_app's responses — branch, don't assume

- **`Registration started …`** — call 1 succeeded; hand over the install link
  and wait (above).
- **`App "{name}" registered …`** — call 2 succeeded; proceed to §4.
- **`guardrails_not_accepted`** — you didn't pass `accept_guardrails: true`; do
  the §1a review, then pass it.
- **`invalid_name` / reserved** — pick another name (you should have caught this
  with `check_name`).
- **`invalid_repo`** — `repo` wasn't a valid `owner/repo` slug (you passed a URL
  or a bare name); fix it.
- **`app_limit_reached`** — the user is at their active-app limit; resolve per
  §1 (offer `stop_app` with confirmation, or an admin raises the limit).
- **`repo_already_registered` / `repo_id_conflict`** — that GitHub repo is
  already bound to an app (one repo binds to at most one app). Use a different
  repo, or manage the existing app via `inno-manage-app`.
- **`repo_mismatch`** — a partially-finished registration exists for this name
  with a *different* repo; finish it with the original repo, or start over with
  a consistent `repo`.
- **`registration_disabled`** — an admin has turned off self-service
  registration; a platform admin must re-enable it (`registration.enabled`).
- Any other non-empty error — surface it verbatim rather than retrying blindly.

## 4. Clone and scaffold

```bash
git clone <the user's repo>     # e.g. git@github.com:<owner>/<repo>.git
cd <repo>
```

After call 2, the repo has been **pruned to the deployment type you chose** —
the template carries both scaffolds and the platform rewrote the repo at
registration. Both types ship the thin `.github/workflows/deploy.yml` caller
workflow (hands-off); a **worker** repo has the TS reference (`app/index.ts`), a
**container** repo the Python/Starlette reference (`app/` + `Dockerfile` +
`lib/`). Everything else — `src/gateway/`, `package.json`,
`package-lock.json`, `tsconfig.json`, and the `wrangler.jsonc` variants — is
injected by the platform at build time and is NOT in the repo; don't create any
of them. Load the `inno-platform-conventions` skill before writing any
application code (stack policy, storage, identity, the do-not-touch file list),
and — for a container app — the `inno-containerize` skill before editing the
Dockerfile.

**Scaffold by the deployment type you chose in §1b** (fetch `get_app_contract`
§1.1 for the authoritative worker deltas):

- **`worker` app (greenfield default):** the entry is **`app/index.ts`**
  exporting `export default { fetch(request, env, ctx) }`. The request is
  already Access-verified — read identity from `request.headers`
  (`X-Forwarded-User` / `X-Forwarded-Groups`), serve **`GET /healthz` as a
  route** (200), and reach storage through the app's **own bindings** —
  `env.DATA` (D1), `env.FILES` (R2) — not `storage.internal`. Declare any npm
  deps in a **non-root** `app/package.json`. The repo is already worker-shaped
  (no Dockerfile, no Python reference — the CI image gates are skipped for this
  type); extend `app/index.ts` rather than re-scaffolding. Never interpolate
  user data into hand-built HTML — even escaped, the SAST gate blocks it; return
  dynamic data as JSON (like the scaffold's `/me`) or use an auto-escaping
  template library. Do NOT create `wrangler.jsonc`/`app-worker.jsonc` — those
  are platform-injected.
- **`container` app, tested stack (Python):** start from the reference app
  (`app/main.py` + `Dockerfile`) and extend it — don't regenerate from scratch.
- **`container` app, another stack:** replace `app/` and the `Dockerfile`
  wholesale for that stack, honoring the contract (port 8080, `/healthz`,
  identity headers, the `storage.internal` endpoints, sign-out link).

**Delete the scaffold marker as you build.** The template repo ships
`app/.needs-build`, which makes CI skip deployment until it's removed. Once you
begin writing the real app (per the approved design), delete it:

```bash
rm -f app/.needs-build
```

Leaving it in place means `inno-ship` will refuse to deploy — by design.

Typical scaffolding steps for a new feature (Python **container** reference
shown; a **worker** app does the equivalent inside `app/index.ts`'s `fetch`
handler — route on the URL, read identity from the request headers, read/write
`env.DATA`/`env.FILES`):
- Add routes to `app/main.py` (container) or `app/index.ts` (worker); split into
  modules under `app/` as it grows.
- (Container, Python) add templates under `app/templates/` — never delete the
  directory while the reference Dockerfile is in use (a missing `templates/` is
  a common runtime 500, see `inno-containerize`).
- Add pinned dependencies to the stack's manifest (`app/requirements.txt` for
  the Python container; `app/package.json` for a worker or a Node container).

**Rewrite `README.md` — this is required, not optional.** The template's README
is inno-template's own ("Use this template…", template internals) and describes
nothing about this app. Replace it with a **high-level overview of the user's
app**: what it does, who it's for, and the app's URL. Keep it short — a few
paragraphs is right; the platform mechanics (identity, storage, CI) already live
in `CLAUDE.md` and don't belong here. The README is the user's file from then
on: they can deepen it to whatever level of detail they prefer, and later
features should keep it truthful.

## 5. Hand off

Once scaffolding is in place, tell the user the app was registered (their repo +
future URL), and that the next steps are: write the app, run
`inno-safety-preflight` locally, then `inno-ship`. Don't push anything yet unless
asked — `inno-new-app`'s job is registration + scaffolding, not deploying.
