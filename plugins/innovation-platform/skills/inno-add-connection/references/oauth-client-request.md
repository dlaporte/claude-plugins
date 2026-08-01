# OAuth client registration request — template for a backend admin

Used from `inno-add-connection` step 3 when the chosen strategy is
`oauth2_code` and the user **cannot self-register** the OAuth client (no
developer-console self-service on that backend) — someone with admin rights
on the backend has to create it. Fill in the placeholders from what discovery
(or the backend's own docs) found, and hand the user this as a copy-paste
request to forward.

---

**Subject:** OAuth client registration request for an integration with
{backend name}

Hi,

We're setting up an integration that needs an OAuth client registered on
{backend name} so it can act on behalf of individual users (each person
authorizes their own access — this is not a shared service account).

Could you register a client with the following:

- **Redirect / callback URL** (exact match, no variations):
  `https://inno-platform.davidlaporte.org/connections/callback`
- **Grant type:** Authorization Code with PKCE (`S256`), i.e. a "web
  application" or "authorization code" client type — not client-credentials
  and not implicit.
- **Token endpoint auth method:** {client_auth — e.g. `client_secret_basic`,
  `client_secret_post`, or "none / public client" if PKCE-only}
- **Scopes requested:** {scopes — list the minimal set the integration needs}
- **Refresh tokens:** {yes/no — say yes if the discovery document advertised
  `refresh_token` support}

Please send back the **client ID** (and **client secret**, if one is issued)
— ideally via a secure/private channel rather than plain email, since the
secret should be treated like a password.

Thanks!

---

Once the admin returns the `client_id` (and `client_secret`, if any), those
are the values to pass to `set_app_connection`'s `client_id` / `client_secret`
arguments alongside the `oauth2_code` config assembled in step 3. Never paste
the secret back into the conversation after it's been sent to the tool —
treat it as already consumed.
