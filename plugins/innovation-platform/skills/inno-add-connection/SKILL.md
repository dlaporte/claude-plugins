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
  (behind the scenes, an OAuth authorization-code login).
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
  { probe_url, delivery: { kind: "bearer" } }
  # or
  { probe_url, delivery: { kind: "header", name: "<header-name>" } }
  ```
  `probe_url` is a cheap "who am I" / identity endpoint the platform calls
  with the pasted token to confirm it actually works before saving it.
  `delivery` says how the app should send the token on real calls — as a
  standard `Authorization: Bearer <token>` header, or under a different named
  header some backends expect. No client registration, no backend admin
  involved — the user creates their own token and pastes it once.

- **`oauth2_code`** — the backend has real user login and you can get (or the
  user can self-register) an OAuth client for it. Config:
  ```
  { authorize_endpoint, token_endpoint, client_auth, pkce, refresh, scopes }
  ```
  filled in from what discovery found (or from the backend's own developer
  docs). The client must be registered against the platform's **single**
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
set_app_connection({ app, connection, label, strategy, config, client_id?, client_secret? })
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

The tool gates the caller to owner-or-admin, SSRF-validates every endpoint
(must resolve to a public HTTPS address — no internal/loopback targets), and
validates the config shape for the chosen strategy. If it rejects the call,
read the message it returns — it's meant to be actionable (a non-public
endpoint, a missing field, a bad strategy/config pairing) — fix the specific
thing named and retry. Tell the user in plain terms what just got stored (the
backend's address and how the app will reach it, kept encrypted on the
platform) — **never echo a secret** (a pasted token, a client secret) back
into the conversation once it's been sent.

To see or remove a Connection later, the platform also has `list_connections`
and `remove_app_connection` — worth knowing about, but not needed for first
setup.

## 5. Wire the app to consume it

In the app's code, use the template's `connections.get(name, callerAssertion)`
helper rather than talking to the backend directly with a stored key:

- Every inbound request to a container-shape MCP app carries an
  `X-Caller-Assertion` header identifying the calling user. Read it and pass
  it straight through: `connections.get("crm", callerAssertion)`.
- On success you get back a live credential for *that* user — an
  `access_token` (or a ready-made `header`, depending on strategy) plus an
  `expires_at`. Use it for the one backend call you're about to make; cache it
  **in memory only**, until `expires_at` — never write it to disk, a database
  row, or a log line.
- On failure with `NotConnected`, don't treat it as an error to swallow —
  relay the connect link it returns (`connect_url`) to the user with this
  exact shape of message: *"You're not connected to {backend} yet — open
  {connect_url} to link your account, then try again."* That's the one time
  this flow surfaces a URL instead of a plain-language sentence — it's a
  real link the user needs to click.
- Add a small `whoami` / status tool or route so the user (and you, while
  testing) can confirm the Connection is live and see which backend identity
  it resolves to, without needing to exercise a real feature first.

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
