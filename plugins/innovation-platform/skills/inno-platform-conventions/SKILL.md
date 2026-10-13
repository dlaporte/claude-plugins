---
name: inno-platform-conventions
description: Use when writing or reviewing code inside an app repo's app/ directory: stack policy, storage, identity, and the files CI will reject if touched. Load this before writing any application code for an Innovation Platform app.
---

# inno-platform-conventions

## Version gate: do this first

Before anything else in this skill, do these five steps in order.

1. If no `inno-platform` tools are available at all, the platform address is
   probably unset. Tell the user to open their platform's panel, copy the
   configure command from its Connect Claude Code card, run it in a terminal,
   and restart Claude Code. Then STOP.
2. Read the `version` field of `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`
   and call the `get_platform_status` MCP tool with it as `plugin_version`.
3. If the `Plugin:` line says `OUTDATED`, `version not reported`, or
   `reported version is not a MAJOR.MINOR.PATCH triple`, STOP. Tell the user
   to run the commands that line gives, then restart Claude Code and start
   again. Do not continue on a stale plugin: its guidance may describe
   platform behavior that no longer exists. If there is no `Plugin:` line at
   all, the platform sets no minimum version: go on to the next step.
4. If the `Plugin:` line says `current` and adds that a newer version
   `is available`, that is advice, not a block. Mention it once, with the
   commands from the `Update commands:` line, and go on to the next step.
5. If the status has no `Template repo:` line, the platform is older than
   v0.15.8. Say so, ask the user's admin to upgrade it, and STOP before any
   step that needs an instance value. Never fall back to a literal value.

Carry on.

The Innovation Platform deploys a Cloudflare Workers gateway (Durable
Object + Container) in front of your app. The gateway is a platform-pinned
build input (the deploy job builds it from the promoted platform source, outside
your checkout; it is never vendored into your repo) and policed by CI; your job
is everything under `app/`. These rules are not
style preferences — each one maps to a CI gate that will fail the deploy.

**Fetch the `get_app_contract` MCP tool before writing app code.** It serves
the platform's full application contract — every requirement (port, health,
identity, storage, protected files), the deployment patterns including what
the platform does NOT support, and the CURRENT digest-pinned recommended
base images. The tool is the live source; never restate contract values from
memory or hard-code a base-image digest.

## Refusals every tool shares

Seven refusals any of the platform's MCP tools can answer are named once, in
the instructions the platform's MCP server sends when a client connects, and
not in each tool's description, which names only the refusals of its own.
When a tool answers one of these, this is what it means:

- `account_inactive`: the caller's account is one Okta no longer lets sign
  in (suspended, deprovisioned or deleted). Every tool, read tools included,
  checks this first, using an answer held for `auth.status_check_minutes`.
  Its message is
  "This account can no longer sign in. Contact a platform admin."
- `rate_limited`: the caller made more calls in a minute than the
  instructions allow. Wait a minute.
- `internal_error`: the call failed in a way the platform did not expect,
  and the failure is logged.
- `forbidden`: the caller lacks the standing the tool's description names.
- `app_not_found`: a tool that takes an app was given a name no app has.
- `invalid_email`: a tool that takes an email address was given a value
  that is not one.
- `upstream_error`: a service the platform calls failed. Its message says
  what failed, and a retry may succeed.

## Deployment types: `container` (below), `function`, `mcp-function`, `mcp-container`

Most of this skill describes the **`container`** type (a Docker container the
gateway fronts). The **`function`** type (the app is its own Cloudflare Worker
behind the *same* gateway) shares everything about identity, releases, and the
gateway boundary, but three specifics differ — the authoritative deltas are in
**`get_app_contract` §1.1**:

- **Entry:** `app/index.ts` exporting `export default { fetch(request, env, ctx) }` —
  no port, no `EXPOSE`, no Dockerfile (`inno-containerize` does not apply).
- **Storage:** the app's **own bindings** — `env.DATA` (D1) / `env.FILES`
  (R2) — instead of `http://storage.internal`. Still no platform credential
  and no cross-app reach; a binding is a handle to the app's *own* resources.
- **Health:** answer `GET /healthz` with **exactly 200** as a **route** in your
  `fetch` handler, not a listening port. A 204, or a redirect to `/healthz/`,
  fails both enforcers.
- **Dependencies:** declare every npm package your Worker imports in
  `app/package.json` and commit `app/package-lock.json` beside it. The install
  rule, what it refuses, and when it runs have one home in this skill: the
  **Node apps** paragraph below. Read it there rather than from a copy here.

The **`mcp-function`** type is a function-type app whose consumer is an MCP client
instead of a browser — every function delta above applies, plus the deltas in
**`get_app_contract` §1.2** (authoritative): serve the MCP **Streamable HTTP**
transport at `POST /mcp` (the MCP TypeScript SDK's
`WebStandardStreamableHTTPServerTransport`, constructed **without a
`sessionIdGenerator`** — stateless, so tools work but server-initiated
features like notifications, sampling, elicitation, and subscriptions do
not); still answer `GET /healthz`; and there is **no Cloudflare Access and no
sign-out link** — the platform is the OAuth Authorization Server, the gateway
is the Resource Server, and the `Authorization` header is consumed before
your code runs (never route `/.well-known/oauth-protected-resource`
yourself). Identity is still `X-Forwarded-User` / `X-Forwarded-Groups`, but
what admits a caller is not the app's Okta group, which is what admits one to
a browser app. An MCP app admits a person when the platform's member list for
the app holds them, or while the app is open to every SSO user, and it reads
both facts at every request (`get_app_contract` §1.2). The groups header is
derived from the same two facts, so a grant, a revoke or a change to open
access reaches your app within the gateway's introspection cache (60 seconds
at most). Every request and every refresh also check that the person's
account may still sign in, using an answer at most `auth.status_check_minutes`
old, so a suspended account stops reaching your app without any change to
the member list.

The **`mcp-container`** type serves that same MCP contract from the container
shape instead — the container baseline below plus `POST /mcp`, for a non-TS/JS
stack or workloads a Cloudflare Worker can't host. Its deltas are
**`get_app_contract` §1.3**, and the Dockerfile rules are `inno-containerize`.

Identity (read the header, never build auth), ephemerality, the
protected/injected files, and the safety-gate discipline below are **identical**
across the types (sign-out applies to the browser-facing types only). The rest
of this skill's code examples are the container reference; translate them into
the `fetch` handler for a function or mcp-function app.

## Releases: push = checks, tag = deploy

A push to the default branch runs the platform's safety gates and deploys
NOTHING: push work-in-progress freely; that run is the safety preflight
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
them CVE-clean: the `deps` gate (pip-audit over `app/requirements.txt`,
`npm audit` over `app/package.json`'s **production** dependencies only, run
`--omit=dev`; since platform v0.14.21, and contract version 21 states it, the
`app-deps` job installs with `--omit=dev` too, so the audited set and the
installed set are the same, and
production code that imports a devDependency at runtime fails the deploy
bundle with an error titled `devDependency imported at runtime`, naming the
package and the fix) and the `container` gate (Trivy at HIGH and CRITICAL
with a fix available, OS and language packages alike, any
stack) fail the build otherwise. One known trap, informational not
prohibitive: older **FastAPI** pins drag in a CVE-bearing Starlette line —
check that the lockfile resolves a clean version before committing to it.

**Node apps: commit `app/package-lock.json`, and declare every import.** For a
function-shaped app (`function`, `mcp-function`) that ships
`app/package.json`, a committed `app/package-lock.json` is required outright
since platform v0.14.2: CI installs with `npm ci --ignore-scripts --omit=dev`
in the `app-deps` job and fails naming the file when the lockfile is missing,
and fails again if it is out of step with `app/package.json`. Since v0.14.14
that job runs on **every
push to the default branch**, so the preflight catches it before you tag; only
the handover of the installed tree to the deploy is tag-gated, and the deploy
job itself runs no package manager in `app/`. (The `deps` gate does still
build a throwaway lockfile to audit when none is committed, so its own green
proves nothing about this.)
Regenerate the lockfile with `npm install` inside `app/` whenever you change
dependencies, and commit both files together. Every package your Worker
imports by bare name must be listed in `app/package.json` itself: nothing is
installed at the repo root any more, so an import that used to resolve by
accident now fails the bundle. For a container app the deploy does not require
the lockfile, but commit it anyway: while an admin has the release-age
cooldown on (`safety.min_release_age_days` above 0), an app shipping
`app/package.json` with no committed, parseable `app/package-lock.json` fails
the `dep-age` gate, because ranges have no single publish date to check. That
app-owned lockfile under `app/` is fine; a lockfile at the **repo root** is a
platform-injected build input and the `config-integrity` gate rejects it.

## Rendering: escape by default, never string-built HTML

Whatever the framework, **never build HTML with string interpolation or
concatenation** — the current user's identity (`X-Forwarded-User`) is
attacker-influenced input (anyone who can reach the gateway with a valid Okta
session controls their own email string, and it flows straight into your
pages), so unescaped interpolation is a stored/reflected-XSS gate: the
`sast` job's semgrep OWASP scan (which covers the whole repository except the
platform-owned root `src/` and the directories semgrep skips by default at any
depth, `test/`, `tests/`, `build/`, `dist/`, `vendor/` and `node_modules/`; your
Dockerfile, `.github/workflows/deploy.yml` and any root-level script are
scanned too) and human review both reject it.
Use your stack's auto-escaping template engine. In the Python reference,
`Jinja2Templates(directory="templates")` autoescapes by default — route all
dynamic content through
`templates.TemplateResponse(request, "page.html", {...})`.

**Response headers.** A browser-facing app (`container`, `function`) should
send a baseline of security headers on its HTML responses, set in one
middleware in the app so they travel with the code through the gated
deploy. Contract §3 recommends it (since platform v0.14.30, contract version
22), and `get_app_security` §9 is the one place that names each header and
gives a starting Content-Security-Policy per deployment pattern, including
how an SPA allows its bootstrap script. Take the headers and the policy from
there, not from memory. For a `container` app the CI run's response-header
report shows what the app sends today. It never blocks a deploy, and it runs
inside the accessibility scan, so it is absent when the app's accessibility
mode is `off`.

## Accessibility: native elements first

Every browser-facing app (`container`, `function`; the two MCP types have no
browser UI) should meet WCAG 2.2 Level AA. Contract §3 recommends it (since
platform v0.14.30, contract version 22), and a school or unit with its own
accessibility policy is governed by that policy. **Fetch the
`get_app_accessibility` MCP tool before writing UI code**: it is the live
source for what that takes. The habits below cost nothing up front, and they
are a reminder, not a substitute for the served notes:

- **Native elements first.** A `<button>` for an action, an `<a href>` for
  navigation, a visible `<label for>` on every input, a native `<dialog>` for
  a modal. A clickable `<div>` has to rebuild by hand everything a button
  already does for a keyboard and a screen reader.
- `<html lang>` and a specific `<title>` on every page, one `<main>`, and
  headings in order.
- **Visible focus.** Never remove the focus outline without a
  `:focus-visible` style in its place.
- **Single-page apps:** a route change updates `document.title` and moves
  focus to the new view.

None of this is a gate by default. For a `container` app the `container` CI
job runs an accessibility report against the built image, and it fails the
deploy only when a platform admin has set the app's `safety.a11y.mode` to
`enforce`; the served notes say what each mode does, and
`inno-safety-preflight` reads the report. A `function` app gets no automated
report, so a review against the served notes is its only check.

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

A listing can be partial. `list_files` returns the keys as an ordinary list
that also carries `truncated`, which is true when the gateway stopped listing
at its cap (`get_app_contract` R5 gives the cap), so the keys are only part
of the bucket: track keys in D1 rather than walk a bucket that size. The JS
client's `listFiles` returns an array with the same flag, not enumerable, so
deep equality and JSON see only the keys. A direct `GET /_storage/files`
answers `truncated: true` beside `keys` only when the listing stopped short.
These are the current template's clients, and the clients are your repo's
own copies. A repo created from an older copy of the template has a listing
that is a plain list with no `truncated`: reading it raises `AttributeError`
in Python, and in JS it is `undefined`, so a partial listing reads as
complete. Check the repo's `app/storage.py` or `lib/storage.js` before
relying on the flag, and if it lacks it, copy the current one from the
template repo (the `Template repo:` line of the status you read in the
Version gate). The current client keeps the old shapes and adds the new
fields, so code written against the old one keeps working.

**Two body caps on that gateway, and the SQL one is the easy one to hit.**
`POST /_storage/sql/query` and `/execute` accept at most **4 MiB** of
`{sql, params}` JSON per request, and so do the
`/_storage/linked/{app}/sql/*` twins a data link exposes. A larger body is
refused `400 bad_request`, which is exactly the answer malformed JSON gets,
so an oversized bulk insert reads as a syntax error rather than a size
problem: send it in batches. `PUT /_storage/files/{key}` is capped
separately, on the object's **declared** `Content-Length`, and over
**25 MiB** the answer is `413 too_large`. Since platform v0.14.21, and
contract version 21 states it, a PUT sent with no `Content-Length` header at
all (a chunked body, for example) is
refused `411 length_required` before the gateway calls R2, which has never
accepted a stream of unknown length. The file cap has been enforced
since the gateway first shipped (2026-07-22), and the SQL body cap since
platform v0.14.17 (2026-09-18); both predate contract version 17, which is
where they were written down. Neither applies to a function-shaped app,
which reaches
`env.DATA`/`env.FILES` with no gateway in between.

## Identity: read the header, never build auth

The gateway has already verified the user against Okta before the request
reaches your container. Read identity via the `current_user(request)` helper
in `storage.py`, or directly:

```python
user = request.headers.get("x-forwarded-user", "unknown")
```

`X-Forwarded-Email` carries the same email as `X-Forwarded-User` — the
gateway injects both, so either one works and neither is more authoritative;
read `X-Forwarded-User` by default and treat `X-Forwarded-Email` as its alias
if you see it in a request dump.

`X-Forwarded-Groups` carries at most two groups, both this app's own, in this
order: the members group when the caller is a member, and the open group when
the caller holds it (on an MCP app, exactly while the app is open). Their
names are in the `App groups:` line of the status you read in the Version
gate, and `app_status` reports the real names. Since contract version 12
(platform v0.14.3) it never carries the platform admin group, another app's
groups, or any other group, so use it only to tell a member from an
open-access visitor; any finer role (an editor, a staff view, an in-app admin)
needs your own role store keyed on `X-Forwarded-User`. Every person an app
admits carries at least one of the two (contract R3, since version 25), so a
visitor admitted only because the app is open carries the open group alone.
An MCP app's two are decided at each request, so a change reaches the header
within the gateway's introspection cache; a browser app's come from the
caller's sign-in, so a change reaches them at their next sign-in. Code that
treats an empty header as "not a member" keeps working, but no admitted
caller arrives with an empty one any more.
The narrowing reaches an MCP app (`mcp-function`, `mcp-container`)
immediately, because the platform narrows its groups before the gateway sees
them. A browser SSO app (`container`, `function`) gets it only at its next
deploy on the v0.14.3 gateway; until then it still receives every
group the caller holds, so an older live app you are debugging may show extra
groups.

From an app's first deploy on the v0.14.3 gateway, the gateway also sets three
proxy headers you may trust: `X-Forwarded-Host`
(the hostname the request arrived on; build links from it),
`X-Forwarded-Proto` (always `https`) and `X-Forwarded-For` (the client address
from Cloudflare's edge, removed when unknown). It deletes `Forwarded` and
drops the Cloudflare Access session cookies. Every other header, including
`X-Real-IP`, `True-Client-IP` and `X-Forwarded-Port`, reaches you exactly as
the client sent it: never use one for identity, origin or an access decision.

**Never implement login pages, sessions, password storage, or an "auth
disabled" dev path**: the gateway strips inbound copies of the headers it owns
before injecting its own verified values, so there is no spoofing surface as
long as you don't add one. `"unknown"` is a reasonable default only for local
dev, never a real auth decision in production code.

## Configuration & secrets (Variables)

App-level values — one API key the whole app shares, a base URL, a feature
flag — are **Variables**: set once with `set_app_variable` (or the app
page's Variables tab), delivered to your running code as ordinary
environment variables. Read them the normal way for your shape:
`os.environ["MY_KEY"]` / `process.env.MY_KEY` in a container app,
`env.MY_KEY` off the fetch handler's `env` in a function-shape worker.
Never commit them (`gitleaks` fails the build on the full history) and
never build a settings page to collect them. Hidden values (the default)
are write-only after saving; a change lands right away and briefly
restarts a container app.

An app may optionally describe the variables it reads in
`app/inno-variables.json` (contract version 15, platform v0.14.16): a JSON
object keyed by variable name, each
value `{"required"?: bool, "secret"?: bool, "description"?: string}` (all
optional; defaults `false`/`true`/empty; description ≤200 chars; ≤32
entries; names follow the same env-var-shaped, non-reserved rule as
`set_app_variable`). The platform sends it on every successful deploy
(the tag's finalize step only; nothing checks it at push time) and it's
purely advisory: declaring a name never sets, blocks, or reserves it. A
file that breaks a rule (a bad name, an unknown or wrong-typed field, more
than 32 entries) is refused whole, with the previous declarations kept and
the deploy left green, and the run log's `deploy-complete:` line is where
that reason surfaces. A file that is not valid JSON, cannot be read, or is
over 32 KB never reaches the platform: the run prints a
`::warning title=Declared variables::` annotation naming the reason instead,
and the deploy still finalizes green (the full rule is `inno-ship`'s
**Declared variables** paragraph). Once declared, `list_app_variables` and the panel's
Variables tab show a required-but-unset name as missing (with your
description), and `app_status` names it directly. Removing a name from the
file removes the declaration on the next deploy, but deleting the whole
file does not: the deploy sends no declaration field at all, and the
previous set keeps being advertised. To clear every name, commit the file
as `{}` rather than deleting it. Write one whenever your app depends on a
variable an owner wouldn't otherwise know to set.

## Per-user backend access (Connections)

Identity above is about *your app* knowing who's using it. Some apps also need
to call **another** service *as that same person* — a per-user API or SaaS
account the app fronts (a departmental system, a niche tool, a dev instance).
For that, use a **Connection** — never a single hardcoded credential shared by
every user. The dividing line: if every user of your app would reach the
backend with the exact same key, that's a plain app secret — a **Variable**
(`inno-manage-app`'s `set_app_variable`, or the app page's Variables tab),
delivered to your code as an ordinary environment variable — not a
Connection; if the backend tells your users apart, it's a Connection.

Consume a Connection with the template's `connections.get(name,
callerAssertion)` helper: read the inbound `X-Caller-Assertion` header off the
current request and pass it straight through — that's what lets the platform
hand back a live credential for *that* caller rather than a shared one. Use
the returned `access_token`/`header` for the one backend call at hand, cache
it in memory only until its `expires_at`, and never write it to disk or a log
line. If the call comes back `NotConnected`, relay the `connect_url` it
returns to the user rather than treating it as a hard failure — a Connection
is expected to be unlinked until the user completes it once.

`ConnectionLocked` (a subclass of `NotConnected`, so an existing
`catch (e) { if (e instanceof NotConnected) … }` still catches it) means
something different and needs different copy: the credential EXISTS, but this
MCP client's authorization predates the user's encryption key, so the platform
cannot open it. **Do not tell the user to reconnect the backend** — connecting
stores a credential, while only a NEW authorization writes the key into the
grant, so reconnecting succeeds and changes nothing and the user loops. Tell
them to **re-authorize this MCP client** (in Claude: `/mcp`, then
re-authenticate that server; removing and re-adding it usually is not enough,
because the client reuses its cached grant). Branch on it if you can:

```js
try {
  const cred = await connections.get("servicenow", callerAssertion);
} catch (e) {
  if (e instanceof ConnectionLocked) {
    return "Re-authorize this connector (/mcp → re-authenticate) and try again.";
  }
  if (e instanceof NotConnected) {
    return `Connect your account first: ${e.connectUrl}`;
  }
  throw e;
}
```

Every seam answer that is not a 2xx reaches your code as a
`ConnectionsError`, from both current template clients (`lib/storage.js` and
`app/storage.py`): `.status` is the HTTP status and `.code` the answer's
`error` code (`null` in JS, `None` in Python, when the body carried none),
so branch on `e.code` for the codes below. In Python it is also an
`httpx.HTTPStatusError`, so an existing `except httpx.HTTPStatusError`
still catches it.

A repo created from an older copy of the template has no `ConnectionsError`:
its JS client throws a plain `Error` with no `.code`, so a paused backend
falls through to your rethrow as a hard failure, and its Python client
raises a plain `httpx.HTTPStatusError`, on which `e.code` raises
`AttributeError`. Check the repo's client before branching on `e.code`, and
if it lacks `ConnectionsError`, copy the current `app/storage.py` or
`lib/storage.js` from the template repo (the `Template repo:` line of the
status you read in the Version gate). It keeps the old shapes: the Python
error is still an `httpx.HTTPStatusError`, and the JS message is still
`connections_error:<status>`. Only the Python message changed, to that same
`connections_error:<status>`, which matters only to code that matches on
`str(e)`.

Five other seam responses are **not** the user's problem and must not be
shown as one:

- **`503 connections_def_disabled`** (named in the contract since version
  25): the connection has been disabled by its owner or a platform admin.
  Transient: the backend is paused, the user's connection is not revoked.
  Treat it like any other transient seam failure and retry later.
- **`503 connections_disabled`** (named in the contract since version 24):
  Connections is not provisioned on this platform. A platform missing its
  gateway key issues no caller assertion, so the app's correct echo arrives
  empty and gets this answer rather than a `400`. Nothing in the app fixes
  it: tell a platform admin, and treat it as a transient seam failure until
  they do.
- **`429 rate_limited`**: the seam's abuse brake, sustained calling past
  120/minute per (app, user). Wait the `Retry-After` interval (60 seconds)
  before retrying; don't relay a `connect_url`, and don't ask the user to
  reconnect.
- **`502 connections_upstream_error`** (named in the contract since version
  21): the backend's own token endpoint failed while the platform was renewing
  the user's credential. A dependency failure, not the user's: retry later,
  and don't relay a `connect_url` or ask the user to reconnect.
- **Any other `503`** (named in the contract since version 25): the
  platform's own Connections setup is broken (a connection's stored
  configuration, a platform key, or a stored credential the platform can no
  longer open). Nothing in the app fixes it: retry later, and tell a
  platform admin.

Two more are the **app's** to fix, not the user's, and never a connect prompt
(contract §2.2 lists both):

- **`401 connections_bad_assertion`**: the caller assertion did not verify,
  almost always because the app echoed one it kept from an earlier request.
  The header is good for 300 seconds from the moment it is minted, so echo
  the `X-Caller-Assertion` of the request you are serving right now.
- **`403 connections_not_declared`**: this app has no connection by that
  name. Check the string you passed against `list_connections`.

Connections are reachable from **`mcp-container`** apps only in v1 — the
other three types can't consume one yet. Setting one up (discovering how the
backend signs people in, choosing among the three strategies — a pasted
token, the backend's own login, or a per-user client ID/secret pair —
and calling `set_app_connection`) is a full workflow of its own: see the
`inno-add-connection` skill rather than wiring this ad hoc.

## Sign out: one link, no session code

Every app includes a "Sign out" link (footer is fine) pointing at the
platform-wide Cloudflare Access logout:

```html
<a href="https://{TEAM_DOMAIN}/cdn-cgi/access/logout">Sign out</a>
```

`{TEAM_DOMAIN}` is environment-specific — **never hard-code it**. Pull it
when scaffolding from the `Sign-out URL (all apps):` line of the status you
read in the Version gate (the `get_platform_docs` tool states this same convention). That is
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
`get_app_logs` MCP tool (the gateway plus your own source, newest first:
container stdout on a container shape, your own Worker on a function
shape). Each line reads `[ts] LEVEL <who> | message`, and `<who>` is the
source: `container` on a line your container wrote to stdout, and Cloudflare's
own origin label on a Worker line. That column separates a
container's output from a Worker's; it does not separate a function app's
gateway from the app's own Worker. Log well now and runtime debugging
(`inno-manage-app`'s Runtime issues guidance) is actually useful later
instead of a wall of noise.

## Keep `ENVIRONMENT=production`

The injected `wrangler.jsonc` (not a file in your repo, see below) pins
`vars.ENVIRONMENT` to `"production"` for every deploy. The gateway's
mock-identity mode (which trusts `X-Mock-User`/`X-Mock-Groups` and skips
Access JWT verification) exists only for the platform's own local tests: it
needs `ENVIRONMENT` set to `"dev"` plus a separate local-only switch, and since
platform v0.14.3 the deploy templater refuses any gateway config that deploys
either, so a deployed gateway cannot mint a mock identity. No app-side gate
re-checks the value: `config-integrity`
stopped inspecting `ENVIRONMENT` when `wrangler.jsonc` stopped being
app-owned. What keeps it honest now is that the gate rejects ANY wrangler
config at your repo root (the scan reads the root directory, it does not
recurse), so no file is left in which to set it, and `ENVIRONMENT` is a
reserved Variable name that `set_app_variable` refuses. This is fully
platform-managed now: you have no `wrangler.jsonc` to edit, so there's
nothing for you to configure or accidentally flip here.

## Files you must not touch

The platform injects several files worker-side at build time, and **none of
them may exist in your repo at all**:

- `src/`, all of it, at the repo root. The platform owns that directory (the
  gateway was bundled from `src/gateway/`), and anything of yours under it (a
  source file, `src/node_modules/`, `src/package.json`, `src/tsconfig.json`)
  could shadow the gateway's dependencies, so the gate fails the repo with a
  "delete src/" message naming what it found. Put your code under `app/`; an
  `app/src/` directory is yours and fine.
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
belongs in your repo. The one exception, checked by content rather than by
absence, is `CLAUDE.md`'s required section headers: the gate checks that five
headers from the template are present (the rest of the file is yours to
extend). **The header check is type-blind.** Three headers are required of
every app, whatever its type: `## Innovation Platform App`, `## Identity (do
not build auth)`, and `## What CI enforces`. The remaining two are variant
groups, and ANY member of a group satisfies the gate: `## Persistence (use the
storage client)` or `## Persistence (use your bindings)`, and `## Container
contract`, `## Function contract`, or the legacy `## Worker contract`, which
still passes. The gate never asks the broker what type your app is, so a
container app carrying the function headers passes, and the reverse passes as
well. If you're hand-authoring `CLAUDE.md` (see `inno-new-app`'s empty-repo
path), copy the template's version for your runtime: `scaffold/function/CLAUDE.md`,
`scaffold/mcp-function/CLAUDE.md`, or `scaffold/mcp-container/CLAUDE.md`
(platform v0.14.5) in the template repo (the `Template repo:` line of the
status you read in the Version gate) for those three types, and
the template's root `CLAUDE.md` for `container`.
Those are the only four: there is no `scaffold/container/`, because the
container files ARE the template root.

Also do not add a competing `wrangler.json` or `wrangler.toml`, or a
`.wrangler/` directory. Wrangler's config discovery order (`wrangler.json` >
`wrangler.jsonc` > `wrangler.toml`) means an unvetted `wrangler.json` would
silently take priority over the platform's injected `wrangler.jsonc` anywhere
discovery decides which config to read. The deploy job pins every wrangler
call to an explicit config (`--config "$GW/wrangler.jsonc"` for the gateway,
which it builds in its own directory outside your checkout, and `--config
app-worker.jsonc` for a function app's own Worker), which is a hard override of
discovery and of redirects, so it is not something a committed file beats. The gate rejection is the independent
belt to that pin: it is what still holds if the pin is ever dropped.

A `scaffold/` directory is rejected too. Registration prunes the template's
deployment-type scaffolds out of your repo, so a surviving `scaffold/` means
the repo is carrying both variants' files. There is one exception: while
`app/.needs-build` is present the directory is allowed, which is what keeps
`config-integrity` green on a freshly generated, not-yet-registered repo's
first run. It buys that one gate and nothing else. Deleting that marker to
start building re-arms the check, so delete `scaffold/` with it.

The gate also rejects root-level `.env` / `.env.*` files (wrangler loads
them at deploy time and adopts unset keys, so a committed
`CLOUDFLARE_API_BASE_URL` would redirect API calls, deploy token included)
and every package manager's project config at the repo root: `.npmrc`,
`.yarnrc`, `.yarnrc.yml`, `.pnpmfile.cjs`, `pnpm-workspace.yaml` and
`bunfig.toml`. A `.npmrc` is rejected at **any** depth, `app/.npmrc`
included: npm reads the `.npmrc` of the directory it runs in and expands
`${VAR}` from the environment into it, which makes it a
credential-exfiltration channel. The other package managers' files are
allowed inside `app/`. Install from the public registry and never commit a
`.npmrc` anywhere.

**No directory symlink anywhere in the repo**, at any depth and dangling ones
too; a symlink that resolves to a *file* stays legal. The gate walks your tree
without following links, so anything behind a directory link is never
inspected, which is how a forbidden file (an `app/.npmrc`, say) could hide
from every check above. `config-integrity` has no policy toggle, so a repo
carrying one cannot deploy until the link is removed. This is the rule that
took the contract to version 14 (platform v0.14.14), and it is not additive: a
repo that passed before can fail its next CI run on it. Keep secrets and local env out of the repo entirely: an
app-level key or config value belongs in a **Variable** (`set_app_variable`,
or the app page's Variables tab), delivered to your code as a real
environment variable.

Everything under `app/` (routes, templates, requirements, your own modules)
is yours to change freely.
