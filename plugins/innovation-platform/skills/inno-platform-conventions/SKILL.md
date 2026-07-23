---
name: inno-platform-conventions
description: Use when writing or reviewing code inside an inno-{app} repo's app/ directory — stack policy, storage, identity, and the files CI will reject if touched. Load this before writing any application code for an Innovation Platform app.
---

# inno-platform-conventions

The Innovation Platform deploys a Cloudflare Workers gateway (Durable
Object + Container) in front of your app. The gateway is a platform-pinned
build input — injected into your repo at build time, not vendored — and
policed by CI; your job is everything under `app/`. These rules are not
style preferences — each one maps to a CI gate that will fail the deploy.

**Fetch the `get_app_contract` MCP tool before writing app code.** It serves
the platform's full application contract — every requirement (port, health,
identity, storage, protected files), the deployment patterns including what
the platform does NOT support, and the CURRENT digest-pinned recommended
base images. The tool is the live source; never restate contract values from
memory or hard-code a base-image digest.

## Deployment type: container (below) or worker

Most of this skill describes the **`container`** type (a Docker container the
gateway fronts). The **`worker`** type (the app is its own Cloudflare Worker
behind the *same* gateway) shares everything about identity, releases, and the
gateway boundary, but three specifics differ — the authoritative deltas are in
**`get_app_contract` §1.1**:

- **Entry:** `app/index.ts` exporting `export default { fetch(request, env, ctx) }` —
  no port, no `EXPOSE`, no Dockerfile (`inno-containerize` does not apply).
- **Storage:** the app's **own bindings** — `env.DATA` (D1) / `env.FILES`
  (R2) — instead of `http://storage.internal`. Still no platform credential
  and no cross-app reach; a binding is a handle to the app's *own* resources.
- **Health:** answer `GET /healthz` with 200 as a **route** in your `fetch`
  handler, not a listening port.

Identity (read the header, never build auth), sign-out, ephemerality, the
protected/injected files, and the safety-gate discipline below are **identical**
for both types. The rest of this skill's code examples are the container
reference; translate them into the `fetch` handler for a worker app.

## Releases: push = checks, tag = deploy

A push to main runs the platform's safety gates and deploys NOTHING — push
work-in-progress freely; that run is the safety preflight
(`inno-safety-preflight` narrates it). Deploys happen only when a `v*`
release tag is pushed (`inno-ship` handles versioning + tagging).

## Stack: the user's choice — Python/Starlette is the tested path

**Python/Starlette is the platform's tested stack**: the template's reference
app (`app/main.py`, plain Starlette) uses it, real platform apps run on it,
and it should work for most implementations — choosing it means starting
from a known-good working example. **Alternative stacks are equally fine**:
the contract is HTTP on port 8080, not a language, and **no CI gate checks
the language or framework**. This holds for new and migrated apps alike
(`inno-migrate-app` keeps the original stack by default) — don't "correct"
an app to Starlette in either direction.

Whatever the stack: pin dependencies in its own manifest under `app/`
(`requirements.txt` for the Python reference — the template's copy is the
source for its pins; `package.json` for Node; `go.mod` for Go; …) and keep
them CVE-clean — the `deps` (pip-audit, Python) and `container` (Trivy, any
stack) gates fail the build otherwise. One known trap, informational not
prohibitive: older **FastAPI** pins drag in a CVE-bearing Starlette line —
check that the lockfile resolves a clean version before committing to it.

## Rendering: escape by default, never string-built HTML

Whatever the framework, **never build HTML with string interpolation or
concatenation** — the current user's identity (`X-Forwarded-User`) is
attacker-influenced input (anyone who can reach the gateway with a valid Okta
session controls their own email string, and it flows straight into your
pages), so unescaped interpolation is a stored/reflected-XSS gate: the
`sast` job's semgrep OWASP scan on `app/` and human review both reject it.
Use your stack's auto-escaping template engine. In the Python reference,
`Jinja2Templates(directory="templates")` autoescapes by default — route all
dynamic content through
`templates.TemplateResponse(request, "page.html", {...})`.

## Persistence: the storage client, never local disk

Container disk is **ephemeral** — it is wiped on every restart and every
redeploy. Never write a local SQLite file, never `open(path, "w")` app data to
disk. Use the storage client shipped in the template (`app/storage.py`):

```python
from storage import Storage

db = Storage()
await db.execute("CREATE TABLE IF NOT EXISTS visits (email TEXT PRIMARY KEY, n INTEGER)")
await db.execute("INSERT INTO visits (email, n) VALUES (?, 1) ON CONFLICT(email) DO UPDATE SET n = n + 1", [user])
rows = await db.query("SELECT n FROM visits WHERE email = ?", [user])
```

`Storage()` defaults its base URL to `http://storage.internal`, which the
gateway's outbound handler intercepts and routes to the app's own D1
database and R2 bucket. **Leave `INNO_STORAGE_BASE` unset** — locally and in
production the default is correct; only override it if you're running the
app process entirely outside the container (unusual). File storage is
`put_file`/`get_file`/`list_files`/`delete_file` against the same client,
backed by R2. Non-Python stacks call the same plain-HTTP endpoints directly
(`POST /_storage/sql/query|execute`, `PUT/GET/DELETE /_storage/files/{key}`,
`GET /_storage/files` — see `get_app_contract` for the table).

## Identity: read the header, never build auth

The gateway has already verified the user against Okta before the request
reaches your container. Read identity via the `current_user(request)` helper
in `storage.py`, or directly:

```python
user = request.headers.get("x-forwarded-user", "unknown")
```

`X-Forwarded-Groups` carries a comma-separated group list (e.g.
`inno-{app}-users`). **Never implement login pages, sessions, password
storage, or an "auth disabled" dev path** — the gateway strips any inbound
copies of these headers before injecting its own verified values, so there is
no spoofing surface as long as you don't add one. `"unknown"` is a reasonable
default only for local dev, never a real auth decision in production code.

### Sign out: one link, no session code

Every app includes a "Sign out" link (footer is fine) pointing at the
platform-wide Cloudflare Access logout:

```html
<a href="https://{TEAM_DOMAIN}/cdn-cgi/access/logout">Sign out</a>
```

`{TEAM_DOMAIN}` is environment-specific — **never hard-code it**. Pull it
when scaffolding from the `Sign-out URL` line of the `get_platform_status`
MCP tool (the `get_platform_docs` tool states this same convention) — that's
the only source available to you now that `wrangler.jsonc` (which carries the
`ACCESS_TEAM_DOMAIN` var the gateway verifies JWTs against) is injected at
build time rather than living in your repo.

It must be the *team* domain, not `/cdn-cgi/access/logout` on the app's own
hostname — the per-app logout clears only that app's cookie, which the
still-live global Access session silently re-issues. The team-domain logout
ends the Access session for **all** platform apps. Known caveat, not a bug:
if the user's Okta session is still alive, revisiting an app signs them back
in without a prompt; a full sign-out on a shared machine also requires
signing out of Okta.

## Logging: stdout, one event per line

Log like it's a contract: one event per line to stdout, plain text or JSON.
That stream is what surfaces in the app's panel **Logs tab** and the
`get_app_logs` MCP tool (container stdout + gateway, newest first) — log well
now and runtime debugging (`inno-manage-app`'s Runtime issues guidance) is
actually useful later instead of a wall of noise.

## Keep `ENVIRONMENT=production`

The injected `wrangler.jsonc` (not a file in your repo — see below) pins
`vars.ENVIRONMENT` to `"production"` for every deploy. That's what keeps the
gateway in real-identity mode; `"dev"` would flip it into mock-identity mode
(trusts `X-Mock-User`/`X-Mock-Groups` headers, skips Access JWT verification)
— an authentication bypass — and the `config-integrity` gate rejects any
deployed app whose `ENVIRONMENT` isn't `production`. This is fully
platform-managed now: you have no `wrangler.jsonc` to edit, so there's
nothing for you to configure or accidentally flip here.

## Files you must not touch

The platform injects several files worker-side at build time, and **none of
them may exist in your repo at all**:

- `src/gateway/` — the Worker code doing JWT verification, request routing,
  and the storage proxy.
- `package.json` and its lockfile (`package-lock.json`) — **at the repo
  root**. Your app's own build files under `app/` (a Node app's
  `app/package.json`, etc.) are yours and fine.
- `tsconfig.json` — repo root only, same rule.
- `wrangler.jsonc` — including its `main` (`src/gateway/index.ts`, the
  injected gateway's entrypoint) and its resource blocks (container
  `max_instances`, D1/R2 bindings, DO migrations).

The `config-integrity` gate fails outright if it finds any of these ("delete
`<file>` — the platform injects …"); never create or restore one locally,
even to "match the template" — there is no version of these files that
belongs in your repo. The one exception checked by diff rather than by
absence is `CLAUDE.md`'s required section headers — the gate checks all five
headers from the template are present (the rest of the file is yours to
extend).

Also do not add a competing `wrangler.json` or `wrangler.toml`, or a
`.wrangler/` directory — Wrangler's config discovery order (`wrangler.json` >
`wrangler.jsonc` > `wrangler.toml`) means an unvetted `wrangler.json` would
silently take priority over the platform's injected `wrangler.jsonc` at both
build and the deploy job's explicit `--config wrangler.jsonc` pin.

The gate also rejects root-level `.env` / `.env.*` files (wrangler loads
them at deploy time and adopts unset keys — a committed
`CLOUDFLARE_API_BASE_URL` would redirect API calls, deploy token included)
and `.npmrc` / `.yarnrc(.yml)` (unpinned package-manager inputs to the
deploy's `npm ci`). Keep secrets and local env out of the repo entirely.

Everything under `app/` (routes, templates, requirements, your own modules)
is yours to change freely.
