---
name: platform-conventions
description: Use when writing or reviewing code inside an inno-{app} repo's app/ directory — the approved stack, storage, identity, and the files CI will reject if touched. Load this before writing any application code for an Innovation Platform app.
---

# platform-conventions

The Innovation Platform deploys a Cloudflare Workers gateway (Durable
Object + Container) in front of your app. The gateway is templated and
policed by CI; your job is everything under `app/`. These rules are not
style preferences — each one maps to a CI gate that will fail the deploy.

## Web framework: Starlette, not FastAPI

Pin `app/requirements.txt` to:

```
starlette>=1.3.1,<2
uvicorn[standard]==0.32.*
httpx==0.27.*
jinja2==3.1.*
```

Use **Starlette directly**, not FastAPI. This isn't a style choice: FastAPI's
transitive Starlette pin historically dragged in `starlette 0.46.x`, which
has known CVEs — the `deps` job's `pip-audit` and the `container` job's Trivy
scan both fail the build on it. The template's reference app
(`app/main.py`) is plain Starlette:

```python
from starlette.applications import Starlette
from starlette.responses import JSONResponse
from starlette.routing import Route
from starlette.templating import Jinja2Templates

app = Starlette(routes=[Route("/healthz", healthz), Route("/", home)])
```

This convention binds template-scaffolded apps. An app brought in by the
`migrate-app` skill may keep its original framework as long as `pip-audit`
and Trivy stay clean — don't "correct" a migrated app to Starlette.

## Rendering: Jinja2 with autoescape on, never string-built HTML

`Jinja2Templates(directory="templates")` autoescapes interpolated values by
default. **Never build HTML with f-strings, `.format()`, or string
concatenation** — the current user's identity (`X-Forwarded-User`) is
attacker-influenced input (anyone who can reach the gateway with a valid Okta
session controls their own email string, and it flows straight into your
templates), so unescaped interpolation is a stored/reflected-XSS gate: the
`sast` job's `semgrep --config p/owasp-top-ten --error app/` and human review
both reject it. Always route dynamic content through
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
backed by R2.

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

## Keep `ENVIRONMENT=production`

`wrangler.jsonc`'s `vars.ENVIRONMENT` must stay `"production"` in the deployed
config. Setting it to `"dev"` flips the gateway into mock-identity mode
(trusts `X-Mock-User`/`X-Mock-Groups` headers, skips Access JWT verification)
— that's an authentication bypass, and the `config-integrity` gate rejects
any deployed app whose `ENVIRONMENT` isn't `production`. The `dev` value only
belongs in the `"dev": { "vars": { "ENVIRONMENT": "dev" } }` block, used by
local `wrangler dev`.

## Files you must not touch

The `config-integrity` gate diffs your repo against `inno-template@main` and
fails the build on any difference in:

- `src/gateway/` (the entire directory — Worker code doing JWT verification,
  request routing, and the storage proxy)
- `package.json` and the lockfile (`package-lock.json`)
- `tsconfig.json`
- `CLAUDE.md`'s required section headers — the gate checks all five
  headers from the template are present (the rest of the file is yours
  to extend)

Also do not add a competing `wrangler.json` or `wrangler.toml`, or a
`.wrangler/` directory — Wrangler's config discovery order (`wrangler.json` >
`wrangler.jsonc` > `wrangler.toml`) means an unvetted `wrangler.json` would
silently override the `wrangler.jsonc` the gate approved and the deploy job
explicitly pins with `--config wrangler.jsonc`. Resource limits inside
`wrangler.jsonc` itself (container `max_instances`, D1/R2 bindings, DO
migrations) are also orchestrator-managed — hand-edits to those fields are
rejected even though the file isn't fully hash-pinned.

Everything under `app/` (routes, templates, requirements, your own modules)
is yours to change freely.
