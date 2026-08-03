# Discovery recipe — figuring out a backend's auth without asking the user to know it

Used from `inno-add-connection` step 2 when the user answers "I'm not sure"
to how people sign in to the backend. This is Claude probing during the
conversation — two `WebFetch` calls and, at most, one unauthenticated API
request. Nothing here sends any of the user's credentials; every request in
this recipe is anonymous.

**Tooling note:** step 1 uses `WebFetch` (it reads a JSON *body*). Step 2 reads
a response **header**, which `WebFetch` does not return — it hands back
processed page content only. Step 2 therefore needs a raw HTTP call via `Bash`
(`curl`), as shown there.

Let `{base}` be the backend's root address (e.g. `https://api.example.com`).

## 1. Try the two standard discovery documents

```
WebFetch {base}/.well-known/openid-configuration
WebFetch {base}/.well-known/oauth-authorization-server
```

Try both — some backends serve one, some the other, some neither. If either
returns JSON (not a 404/HTML error page), you've confirmed the backend
speaks OAuth — but read `grant_types_supported` before concluding it has a
user sign-in path (a client-credentials-only document routes to a different
strategy; see below). When `authorization_code` is offered, the document
gives you most of the `oauth2_code` config directly:

| Field in the discovery document | Where it goes | How to translate it |
| --- | --- | --- |
| `authorization_endpoint` | `config.authorize_endpoint` | copy as-is |
| `token_endpoint` | `config.token_endpoint` | copy as-is |
| `revocation_endpoint` | `config.revocation_endpoint` | copy as-is; **omit if the document doesn't advertise one**. Setting it lets a user's disconnect actually revoke their token at the backend rather than only forgetting it platform-side. |
| `token_endpoint_auth_methods_supported` | `config.client_auth` | this is an **enum, not a copy**: `client_secret_basic` → `"basic"`, `client_secret_post` → `"post"`. If the only method is `none` (public client, PKCE-only), **omit `client_auth` entirely** and register the client without a secret. If both basic and post are offered, prefer `"basic"`. |
| `code_challenge_methods_supported` includes `S256` | `config.pkce` | `true` (a boolean — prefer PKCE whenever offered; if the field is absent, default `false`) |
| `scopes_supported` | the **top-level `scopes` arg** of `set_app_connection` (a `string[]`), *not* `config` | pick the minimal set the app actually needs, not the whole list. Passing `scopes` as a top-level arg is the canonical place — it takes precedence over any `config.scopes` at connect time. |
| `grant_types_supported` includes `refresh_token` | `config.refresh` | this is an **enum, not a boolean**: set `"static"` (the safe default — most providers return the same refresh token each time), or `"rotating"` **only if** the backend's own docs say it issues a fresh refresh token on every refresh. If `refresh_token` is **absent** from `grant_types_supported`, set `"none"`. |

One reading of this document changes the strategy outright:
`grant_types_supported` of **only** `["client_credentials"]` — no
`authorization_code` at all (Aruba Central / HPE GreenLake's AS metadata is
exactly this shape). That backend has no user sign-in flow to delegate to;
if each user can create their own API client in its portal, use
**`oauth2_client_creds`** instead: copy `token_endpoint` as-is, map
`token_endpoint_auth_methods_supported` the same way as above (into the
optional `config.client_auth`, default `"post"`), ignore
`authorization_endpoint`/`revocation_endpoint`/`pkce`/`refresh` (none apply),
and skip client registration entirely — no callback URL, no definition-level
client_id/client_secret.

Report back to the user in plain terms, matched to the strategy the document
routed you to. For the sign-in path (`oauth2_code`): *"Good news — {backend}
uses the same sign-in as its website, so you'll just log in there once to
connect."* — and confirm the scopes you intend to request in plain language
("read your tickets," not the raw scope string) before moving to
provisioning. For the client-credentials-only shape (`oauth2_client_creds`):
*"{backend} works with API clients — you'll create one in your own {backend}
account and paste its ID and secret once; the platform handles the rest."*

## 2. No discovery document? Read `WWW-Authenticate` from an unauthenticated hit

If neither `.well-known` document resolves, make **one** unauthenticated
request to a representative API path on the backend (something you'd expect
to require auth — a list or "me" endpoint is ideal) and inspect the response
**headers**. Use `curl` from `Bash`, not `WebFetch` — the answer here is a
header, and `WebFetch` returns processed body content:

```bash
curl -sS -m 10 -D - -o /dev/null "{base}/<a-path-that-requires-auth>"
```

`-D -` dumps the status line and response headers to stdout; `-o /dev/null`
discards the body. Stay on `GET` (many APIs reject `HEAD` with a 405 and no
`WWW-Authenticate` at all). Do not send any credentials — the point is to see
how the backend tells an anonymous caller it needs auth. Then branch on what
came back:

- **`WWW-Authenticate: Bearer ...`** (look for a `realm` and possibly an
  `error="invalid_token"` or scope hint) — the backend expects a bearer
  token on every call, but advertised no OAuth discovery document. This is
  usually a personal-access-token backend: propose `secret_form` with
  `delivery: { kind: "bearer" }`, and ask the user (or check the backend's own
  docs) for where in their account they'd generate that token, and what a
  cheap "who am I" endpoint looks like for `probe_url`.
- **`WWW-Authenticate: Basic realm="..."`** — HTTP Basic. If the backend's own
  docs show people using their *account username + password* here, stop and
  tell the user plainly that this backend can't be connected today — the
  platform never stores raw passwords. If instead the backend's convention is
  "put your API token in as the username, leave the password blank" (a common
  pattern for some SaaS APIs), that's still effectively a pasted token; note
  it as a `secret_form` case but flag to the user that the exact header
  encoding needs to match what `delivery` supports (`bearer` or a named
  header) — if it doesn't cleanly fit either, this is a case to raise rather
  than force.
- **No `WWW-Authenticate` header, or a 200 on the unauthenticated call** — the
  endpoint you probed doesn't require auth, or auth works some other way; try
  a different path, or fall back to asking the user directly (check their
  account settings for anything called "API key," "personal access token," or
  "developer settings," which almost always means `secret_form`).

## 3. When it's still unclear

Don't loop indefinitely on probing. One round of the two discovery documents
plus one unauthenticated API request is enough signal to report back and ask
the user to confirm or correct — they can usually tell you which bucket
they're in once you've narrowed it to a plain-language question ("does your
account have a page for creating API tokens?").
