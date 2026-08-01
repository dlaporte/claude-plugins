---
name: inno-add-connection
description: Use when an app needs to reach an external backend AS EACH INDIVIDUAL USER — a per-user API or SaaS account the app fronts (a departmental system, a niche tool, a dev instance) — rather than with one shared app key. Discovers how people sign in to that backend, provisions a Connection with set_app_connection (a pasted token or the backend's own login), and wires the app to consume it. mcp-container apps only in v1.
---

# inno-add-connection

Some apps don't just read/write their own database — they call out to another
service **on behalf of the person using them**, and that other service needs
to know *which* person it's talking to. A Connection is the platform's way of
handing your app a live, per-user credential for that outside service without
your app ever holding a master key to everyone's accounts. This skill walks
through recognizing when that's what you need, figuring out how the backend
signs people in, setting the Connection up, and wiring the app's code to use
it.

Requires the `inno-platform` MCP server (ships with this plugin's `.mcp.json`).
If this is the first call against it this session, expect a browser Okta
login — that's expected, not an error.

**Speak the user's language.** Match the rest of this plugin: use plain terms
with the user — "connect your app to {backend} as each person," "sign in to
{backend} once," "a token you create in your {backend} account and paste in."
Don't say "OAuth," "PKCE," "client secret," or name the platform's own
providers (Cloudflare, Okta, wrangler) unless the user is clearly technical.
Those words are fine in your own reasoning and in the tool calls you make —
just not in the sentences you say back to a non-technical user.

**No catalog, no steering.** This skill doesn't maintain or suggest a list of
backends. If the target is a big enterprise service that already has its own
first-party integration for AI assistants, it's fine to mention that exists —
but don't block or discourage the user from connecting to it this way either.
This path is most useful for the long tail: a departmental API, a small
internal tool, a niche SaaS, a dev/test instance — anything without a
ready-made integration.

## 1. Confirm this app actually needs a Connection

Check all three before doing anything else:

- **Per-user, not shared.** A Connection is for a backend where each person
  sees or does *their own* things — the backend itself tells users apart. If
  every user of your app would use the exact same key/token to reach the
  backend (one shared service account), that's **not** a Connection — it's a
  plain app secret. Point the user at `inno-platform-conventions` (which draws
  this same line) and `inno-manage-app`'s `set_config`/`remove_config` instead,
  and stop here.
- **The app is `mcp-container`.** Only container-shaped MCP apps can reach the
  platform's Connections seam in v1. If the app is `function`, `mcp-function`,
  or plain `container`, say plainly that this app type can't consume a
  Connection yet, and stop — don't half-wire it. (If you're not sure of the
  app's type, check `app_status` or ask the user; a `container` app that only
  serves a browser UI, with no MCP endpoint, is also out of scope today.)
- **The user owns or administers the app.** `set_app_connection` (like every
  other app-scoped tool) is gated server-side to the app's owner or a platform
  admin — a `forbidden` response means exactly that; don't try to work around
  it locally.

If any of these isn't true, explain which one in plain terms and stop.

## 2. Find out how people sign in to the backend

Ask the user, in plain terms, how people currently get into the backend
day-to-day. Offer it as a short choice, not open-ended jargon:

- **"They log in on the backend's own website"** — likely the sign-in path
  (behind the scenes, an OAuth authorization-code login). But don't stop
  there: many backends that people log into *also* let each user mint a
  personal token in their account settings. If they do, that paste-a-token
  path is the better choice here — it needs no client registration and no
  backend admin — so ask the follow-up: "Can you also create an API key or
  personal token inside your {backend} account?" A "yes" moves you to the
  paste path even though people normally log in on the website.
- **"They create a token or key in their account settings and paste it
  somewhere"** — the paste-a-token path.
- **"I'm not sure"** — probe for the answer instead of guessing. Fetch the
  backend's discovery documents and make one unauthenticated request to read
  how it responds; see `references/discovery.md` for the exact recipe (which
  URLs to try, what the response tells you, and how to fill in the
  configuration fields from it). Report what you found back to the user in
  plain terms — e.g. "It looks like {backend} uses sign-in with your account,
  the same way it does in a browser" or "It looks like {backend} issues
  personal tokens you'd create in your account settings" — and confirm before
  moving on. If discovery comes back inconclusive, fall back to asking the
  user directly, or ask them to check their backend account's settings page
  for anything called "API key," "personal access token," or "developer
  settings."

## 3. Choose the strategy and fill in the configuration

Two strategies. Prefer the first whenever the backend supports it — it needs
no cooperation from anyone else.

- **`secret_form`** (preferred, zero-admin) — the backend issues
  user-generatable tokens (a personal access token / API key created in
  account settings). Config:
  ```
  { probe_url, delivery: { kind: "bearer" }, help_text }
  # or
  { probe_url, delivery: { kind: "header", name: "<header-name>" }, help_text }
  ```
  `probe_url` is a cheap "who am I" / identity endpoint the platform calls
  with the pasted token to confirm it actually works before saving it.
  `delivery` says how the app should send the token on real calls — as a
  standard `Authorization: Bearer <token>` header, or under a different named
  header some backends expect. `help_text` is **strongly recommended**: it's
  the instruction line the platform shows the user on the connect form, right
  above the paste box — this is the *only* place they're told where to get the
  token, so without it they face a blank box. Make it a plain, specific
  sentence, e.g. *"Create a personal access token at Settings → Developer →
  Tokens in your Acme account, then paste it here."* (This is exactly the
  answer to the "where do you create that token?" question from step 2.) No
  client registration, no backend admin involved — the user creates their own
  token and pastes it once.

- **`oauth2_code`** — the backend has real user login and you can get (or the
  user can self-register) an OAuth client for it. Config:
  ```
  { authorize_endpoint, token_endpoint, client_auth, pkce, refresh,
    revocation_endpoint? }
  ```
  filled in from what discovery found (or from the backend's own developer
  docs), where:
  - `client_auth` is `"post"` or `"basic"` — **omit it entirely** for a
    public (secret-less) client.
  - `pkce` is a boolean (prefer `true`).
  - `refresh` is one of `"static"` (default), `"rotating"`, or `"none"` — see
    `references/discovery.md` for which to pick.
  - `revocation_endpoint` is **optional but worth setting** when the backend
    (or its discovery document) advertises one: it's where the platform calls
    to revoke a user's token at the backend when they disconnect. Omit it and
    a disconnect still forgets the token platform-side, but **never revokes it
    at the backend** — the credential stays live there until it expires.

  `scopes` is **not** part of `config` — pass it as a **top-level arg** of
  `set_app_connection` (a `string[]`; see step 4). The client must be
  registered against the platform's **single**
  callback URL, the same for every app and every backend:
  ```
  https://inno-platform.davidlaporte.org/connections/callback
  ```
  If the user can self-register a client (many developer-console backends let
  any account owner do this), have them do it and hand you the `client_id` /
  `client_secret`. If they can't — it needs a backend admin — generate the
  exact request to send that admin instead of asking the user to become an
  OAuth expert: see `references/oauth-client-request.md` for the template
  (endpoints, the callback URL, the grant type, in copy-paste form).

## 4. Provision the Connection

Call the `set_app_connection` MCP tool:

```
set_app_connection({ app, connection, label, strategy, config,
                     client_id?, client_secret?, scopes?, disabled? })
```

- `app` — the app's registered name.
- `connection` — a short machine-safe name for this backend within the app
  (e.g. `crm`, `ticketing`) — this is the string the app's code will pass to
  `connections.get(...)` later.
- `label` — a human-readable name shown back to the user when they connect
  (e.g. "Acme CRM").
- `strategy` — `"secret_form"` or `"oauth2_code"` from step 3.
- `config` — the shape from step 3.
- `client_id` / `client_secret` — only for `oauth2_code`.
- `scopes` — optional `string[]`, the OAuth scopes to request (only meaningful
  for `oauth2_code`). This top-level arg is the canonical place for scopes and
  wins over any `config.scopes`; pass the minimal set the app needs.
- `disabled` — optional `boolean`. Set `true` to register the connection in a
  **paused** state (the seam returns "unavailable" for all users until you
  re-enable it); omit or `false` for the normal case. Pausing is a reversible
  switch, **not** a per-user credential wipe — stored credentials are kept and
  resume when re-enabled. Calling again with the opposite value flips it.

The tool gates the caller to owner-or-admin, SSRF-validates every endpoint
(must resolve to a public HTTPS address — no internal/loopback targets), and
validates the config shape for the chosen strategy. If it rejects the call,
read the message it returns — it's meant to be actionable (a non-public
endpoint, a missing field, a bad strategy/config pairing) — fix the specific
thing named and retry. Two responses that are **not** rejections, so don't
retry blindly:

- **"set CONNECTIONS_ENC_KEY on the platform first"** — a real precondition,
  not a bad argument: passing a `client_secret` requires the platform's
  encryption key to already be configured. If you hit this, the platform
  hasn't finished its Connections setup yet — surface it rather than reshaping
  the call (nothing you change in the args fixes it).
- **A "rotating" refresh warning** — if you set `refresh: "rotating"`, the
  tool returns a warning that the platform has no per-user refresh lock, so
  concurrent refreshes for one user can race into a spurious disconnect. This
  means the call **succeeded** (rotating is supported) — treat it as a flag to
  relay, not a failure to retry.

Tell the user in plain terms what just got stored (the backend's address and
how the app will reach it, kept encrypted on the platform) — **never echo a
secret** (a pasted token, a client secret) back into the conversation once
it's been sent.

**Updating a Connection later is a full replace, not a merge.** Re-calling
`set_app_connection` for the same `app`+`connection` overwrites `label`,
`strategy`, `config`, and `scopes` with whatever you pass — so resend all of
them, not just the field you're changing (omitting `scopes`, for instance,
silently clears it). The exceptions: `client_secret` and `disabled` are safe
to omit — an omitted `client_secret` keeps the stored one, and an omitted
`disabled` leaves the enabled/paused state as-is. To see or remove a
Connection, the platform also has `list_connections` and
`remove_app_connection`.

## 5. Wire the app to consume it

In the app's code, use the template's `Connections` helper (from `storage.py`
in a Python container, `storage.js` in a JS one) rather than talking to the
backend directly with a stored key. The whole trick is passing through **this
request's** `X-Caller-Assertion` header — that header is what lets the platform
hand back a credential for *the calling user* rather than a shared one.

**Reading the header inside an MCP tool (Python + FastMCP — the mcp-container
default stack).** A FastMCP tool isn't handed the raw HTTP request as an
argument, so reach for it through FastMCP's request-context dependency
(`get_http_request`, from the same `fastmcp.server.dependencies` module that
provides `get_access_token`):

```python
from fastmcp.server.dependencies import get_http_request
from storage import Connections, NotConnected  # template helpers

connections = Connections()  # points at http://storage.internal by default

@mcp.tool()
async def list_incidents() -> dict:
    # X-Caller-Assertion is present on every gateway-forwarded request;
    # header lookup is case-insensitive.
    caller_assertion = get_http_request().headers.get("x-caller-assertion")
    try:
        cred = await connections.get("crm", caller_assertion)
    except NotConnected as e:
        # Do NOT swallow this — surface the link so the user can link once.
        return {"error": f"You're not connected to your CRM yet — open "
                         f"{e.connect_url} to link your account, then try again."}
    # cred is {"access_token": ..., "header": ..., "expires_at": ...}
    token = cred["access_token"]
    # ... make the backend call with `token`; keep it in memory only ...
```

(If you're on the official MCP Python SDK's FastMCP rather than the standalone
`fastmcp` package, the same inbound header is reachable from the tool's request
context — read `x-caller-assertion` there and pass it through identically. In a
JS container, `connections.get(name, callerAssertion)` takes the assertion you
read off `request.headers` in your `POST /mcp` handler.)

Rules that hold regardless of language:

- **Pass the real inbound assertion, never a fabricated one.** Read it off the
  current request and pass it straight through; don't hardcode, cache across
  users, or invent one.
- On success you get back a live credential for *that* user — an
  `access_token` (or a ready-made `header`, depending on strategy) plus an
  `expires_at`. Use it for the one backend call you're about to make; cache it
  **in memory only**, until `expires_at` — never write it to disk, a database
  row, or a log line.
- On `NotConnected`, don't treat it as an error to swallow — relay the connect
  link it returns (`connect_url`) to the user with this exact shape of message:
  *"You're not connected to {backend} yet — open {connect_url} to link your
  account, then try again."* That's the one time this flow surfaces a URL
  instead of a plain-language sentence — it's a real link the user must click.
- Add a small `whoami` / status tool so the user (and you, while testing) can
  confirm the Connection is live and see which backend identity it resolves to,
  without needing to exercise a real feature first.

## 6. Verify

After shipping, have the user open the connect link once: they either sign in
on the backend's own page (`oauth2_code`) or paste the token they generated
(`secret_form`). From then on, every tool call the app makes to that backend
runs as them, automatically — nothing to repeat per session. Confirm it
worked using the `whoami`/status affordance from step 5 before calling the
feature done.

## References

- `references/discovery.md` — the exact probe recipe for step 2 (which
  `/.well-known/*` documents to fetch, how to read a `WWW-Authenticate`
  header, and how each finding maps to a config field).
- `references/oauth-client-request.md` — the copy-paste request template for
  step 3 when a backend admin needs to register the OAuth client.
