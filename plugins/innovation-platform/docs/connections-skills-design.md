# Connections skills (Phase 2) — design + plan

> **HISTORICAL DESIGN DOCUMENT — not current documentation.**
> Written: 2026-08-01 · Outcome: IMPLEMENTED-AS-DESCRIBED (shipped in PR #4)
> Live docs: `skills/inno-add-connection/SKILL.md` and its
> `references/{discovery,oauth-client-request}.md`;
> `skills/inno-platform-conventions/SKILL.md` § "Per-user backend access
> (Connections)". Platform-side: `docs/APP-CONTRACT.md` § 2.2, served by the
> `get_app_contract` MCP tool.
>
> Nothing below is maintained. Where it disagrees with the shipped skills, the
> skills are right.

**Date:** 2026-08-01
**Status:** IMPLEMENTED-AS-DESCRIBED (PR #4) — every path in the File plan
below exists; the two `references/` files that section marks optional both
shipped. *(This line read "proposed → implementing" and was never updated.)*
**Deliverable:** teach a user's Claude Code, through the innovation-platform
plugin skills, to add a per-user backend **Connection** to an app it is
building or migrating — including auto-discovering the backend's auth mechanism
— in plain language for a broad, mixed-technical population.
**Depended on:** the platform Connections capability (self-service, app-scoped,
merged to `dlaporte/inno-platform` main) and the `connections.get()`
client-library helper in `dlaporte/inno-template` — which **shipped**, in the
template's clients (`lib/storage.js` and `app/storage.py`); the contract states
it un-hedged.

## Why

The platform now brokers per-user backend credentials (Connections): an app
owner registers a backend for their own app with `set_app_connection`, and the
app fetches a live per-user credential from the seam. But **no skill mentions
any of this** — so a user's Claude Code building or migrating a backend-fronting
MCP today wouldn't know Connections exists, and would fall back to hardcoding a
credential or building a sidecar. This closes that gap and, per the owner's
priority ("anything we can do to assist them in building"), adds **backend
auth-discovery** so Claude figures out the backend's auth for the user rather
than making them know and type it.

## Principles (inherit the plugin's house style)

1. **Plain language, non-technical-user-first.** Match `inno-new-app`'s rule:
   do NOT name providers/technologies (Cloudflare, Okta, OAuth internals) unless
   the user is clearly technical. Speak of "connecting your app to {backend} as
   each user," "signing in to {backend} once," "a token you create in your
   {backend} account." The mechanism stays behind plain verbs.
2. **No curated backend catalog.** Enterprise services already have first-party
   MCPs; don't nudge users toward standing up parallel paths to them — and don't
   actively discourage. The target is the long tail (a departmental API, a niche
   SaaS, a dev instance).
3. **The paste-a-token path is the workhorse.** `secret_form` (the user creates
   a token in their own backend account and pastes it) needs **no backend admin**
   and is the primary self-service path. `oauth2_code` (the user completes the
   backend's own login) is used where an OAuth client is obtainable.
4. **Discovery is Claude probing during the conversation**, not a new program:
   Claude fetches the backend's `/.well-known/*` and reads `WWW-Authenticate`,
   then proposes a filled-in configuration for the user to confirm.
5. **Per-user, not app-level.** Connections is for credentials that differ per
   user. A single shared API key for all users is plain env-secret config, NOT
   a Connection — the skill must draw this line.

## The new skill: `inno-add-connection`

A workflow skill (verb-noun, like `inno-migrate-app`). Triggered when an app
needs to act **as each individual user** on an external backend.

**SKILL.md workflow:**

1. **Gate / detect.** Confirm three things, else stop:
   - The app fronts an external backend that enforces **per-user** identity
     (each user sees/does different things). If it's one shared key for everyone
     → that's an app secret (point at `inno-platform-conventions` secrets), not
     a Connection.
   - The app is **container-shape (`mcp-container`)** — only those can reach the
     `/_connections` seam in v1. A function-shape app can't consume a Connection
     yet; say so plainly and stop.
   - The user owns (or admins) the app.

2. **Discover the backend's sign-in** (plain tiered ask + probe). Ask, in plain
   terms, how people sign in to the backend:
   - "They log in on the backend's own website" → likely the OAuth path.
   - "They create a token/key in their account settings and paste it" → the
     paste path.
   - "I'm not sure" → **probe**: WebFetch `{base}/.well-known/openid-configuration`
     and `{base}/.well-known/oauth-authorization-server`; if present, the app
     uses the OAuth path and the document gives the sign-in/token addresses,
     PKCE support, and scopes (fill the config from it). Also make one
     unauthenticated request to a backend API path and read the
     `WWW-Authenticate` response header (`Bearer` → OAuth/token; `Basic` →
     unsupported, the platform never stores passwords). Report what was found in
     plain terms and confirm with the user.

3. **Choose the strategy + assemble the config:**
   - **`secret_form`** (preferred, zero-admin) when the backend issues
     user-generatable tokens (personal access token / API key): config =
     `{probe_url, delivery: {kind: "bearer"} | {kind: "header", name}}` — a cheap
     "who am I" endpoint the platform hits to validate the pasted token, plus how
     to send it. The user creates a token in their account; no backend admin.
   - **`oauth2_code`** when the backend has user login + an OAuth client is
     obtainable: config = `{authorize_endpoint, token_endpoint, client_auth,
     pkce, refresh, scopes}` (from discovery). Needs a client id + secret
     registered at the backend against the **single platform callback URL**
     (`https://inno-platform.davidlaporte.org/connections/callback`). If the user
     can't self-register the client, generate the exact copy-paste request to
     hand their backend admin (endpoints, the callback URL, "auth-code + PKCE").

4. **Provision.** Call `set_app_connection` (inno-platform MCP) with
   `{app, connection, label, strategy, config, client_id?, client_secret?}`. The
   tool gates owner-or-admin, SSRF-validates the endpoints (public HTTPS only),
   and validates the config shape — if it rejects, read the teachable message
   and fix (e.g. a non-public endpoint, a missing field). Tell the user in plain
   terms what's stored (the backend's address and the app's credentials,
   encrypted) — never echo a secret.

5. **Consume (write the app code).** Use the template's `connections.get(name,
   callerAssertion)` helper: the app reads its inbound `X-Caller-Assertion`
   header (present on every request) and passes it; use the returned
   `access_token` (or `header`) on the backend call, cache it in memory until
   `expires_at`, never to disk, never logged. On `NotConnected`, the tool returns
   the connect link to the user — the **tool-copy convention**: *"You're not
   connected to {backend} yet — open {connect_url} to link your account (one
   time), then try again."* Provide a small `whoami`/status affordance.

6. **Verify.** After ship, the user opens the connect link, completes the backend
   sign-in (OAuth) or pastes their token (secret_form) once, and the app's tools
   then run as them. Confirm via the status/whoami tool.

Optionally add `references/` files: `discovery.md` (the probe recipe + how to
read a discovery doc / WWW-Authenticate) and `oauth-client-request.md` (the
backend-admin request template), to keep SKILL.md lean.

## Edits to existing skills

- **`inno-platform-conventions/SKILL.md`** — add a "Per-user backend access
  (Connections)" subsection near identity/storage: when your app must act as
  each user on an external backend, use a Connection (not a shared key); consume
  via `connections.get(name, assertion)` echoing the inbound X-Caller-Assertion;
  relay `connect_url` on `NotConnected`; container-shape only in v1; pointer to
  `inno-add-connection` for setup.
- **`inno-new-app/SKILL.md`** — add an intake step: "Does the app act as each
  user on an external backend? If so, set up a Connection (`inno-add-connection`)
  after the app is registered."
- **`inno-migrate-app/SKILL.md`** — in the assessment, flag a repo that currently
  runs its own backend OAuth / holds a per-user backend token / uses a sidecar:
  that's exactly what Connections replaces — point at `inno-add-connection`
  instead of porting the old auth. (Complements the existing "auth to strip"
  guidance, which is about the *platform* login, not the *backend* login.)

## Decisions (ratify)

Plain-language & non-technical-first; no curated catalog; `secret_form` primary /
`oauth2_code` where a client's obtainable; discovery = Claude probing
`/.well-known/*` + `WWW-Authenticate`; per-user-only (shared key ≠ Connection);
container-shape (`mcp-container`) only in v1; the tool-copy convention for
`not_connected`; secrets live platform-side, never in the repo.

## Out of scope

The platform code (done); function-shape/sso-container support; the house
`building-secure-mcp-servers` profile (owner-deferred); `oauth2_device` /
`token_exchange` strategies (not built).

## File plan

*All of these shipped in PR #4 — the NEW/MODIFY markers are the plan's, not a
description of outstanding work.*

```
plugins/innovation-platform/skills/inno-add-connection/SKILL.md      NEW
plugins/innovation-platform/skills/inno-add-connection/references/    NEW (discovery.md, oauth-client-request.md)
plugins/innovation-platform/skills/inno-platform-conventions/SKILL.md MODIFY (+ Connections consume subsection)
plugins/innovation-platform/skills/inno-new-app/SKILL.md              MODIFY (+ intake step)
plugins/innovation-platform/skills/inno-migrate-app/SKILL.md          MODIFY (+ backend-auth → Connections note)
(plugin manifest / skill listing if one enumerates skills)            MODIFY if present
```
