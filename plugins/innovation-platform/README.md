# innovation-platform

Claude Code plugin for the davidlaporte.org Innovation Platform. Bundles the
`inno-platform` MCP server and eight skills that walk Claude through the whole
app lifecycle: create (or migrate existing code), write, containerize,
connect to a per-user backend, gate-check, ship, and manage. Apps deploy as
one of four **types** behind the
same identity gateway: a **container** (any stack, a Dockerfile, and the type
`register_app` defaults to when none is given), a **function** (its own
Cloudflare Worker, JS/TS), an **mcp-function** app (an MCP server in its own
Cloudflare Worker behind the OAuth gateway), or an **mcp-container** app (an
MCP server in a Docker container, any language, behind the same OAuth
gateway). The type is chosen at `register_app`.

**Repos are user-owned.** An app is created by **registering a GitHub repo you
own**. You create a repo from the public `inno-template` ("Use this template" →
your own account or org, so it lands already scaffolded in your ownership),
and the `register_app` MCP tool provisions the app's resources and binds them
to your repo. `register_app` is a two-call flow with two steps in between: the
first call returns a proof-of-control file (a path under `.inno-platform/` and
its exact contents) plus the platform GitHub App's install link (and points at
the template for creating the repo); you commit that file on the repo's DEFAULT
branch and install the App on the repo; the second call, with the same
arguments, verifies both, finishes, and returns your `deploy.yml`. Installing
the App proves the platform can see the repo; the committed file proves you can
change it, and registration refuses with `repo_control_unproven` until it is
there. There is no platform-owned repo: the repo is yours (any account, public
or private), and uninstalling the App unlinks and stops the app. (The old
`create_app` tool has been retired.)

## Install

```
/plugin marketplace add dlaporte/claude-plugins
/plugin install innovation-platform@davidlaporte
```

The first tool call against the `inno-platform` MCP server (e.g. from the
`inno-new-app` skill's `register_app`) opens a browser window for an **Okta
login**.
This is expected — the MCP server authenticates you as yourself so every
action it takes (creating an app, granting access, stopping or starting one)
is attributable to your real Okta identity, not a shared service credential.
**If the connector was NOT already authorized when your Claude Code session
started, authorizing it mid-session (e.g. via `/mcp`) is not enough** — the
MCP client enumerates tools at startup, so `inno-platform`'s tools stay
uncallable even after `claude mcp list` shows it `✔ Connected`. Restart the
session once authorization completes; only then are the tools callable.

### Keeping the plugin current

Every skill opens by passing this plugin's `version` to `get_platform_status`,
which holds the minimum version the platform accepts and answers on a
`Plugin:` line. **OUTDATED stops the skill dead**, as does a version the
platform could not read: stale guidance describes behavior that no longer
exists, and skills added since your build are simply missing. The same line
advises, without blocking, when a newer version than yours is available.
Either way the fix is two commands:

```
claude plugin marketplace update davidlaporte
claude plugin update innovation-platform@davidlaporte
```

Restart Claude Code afterwards. An installed plugin is cached per version, so
without those two commands nothing tells a user they are on an old build.

### House style

Every skill in this plugin speaks to a broad, largely non-technical userbase,
so the sentences you say back to a user use plain terms: "access", "a
database", "file storage", "your app's address", "sign-in". Do **not** name
specific technologies or providers (Cloudflare, D1, R2, Okta, Workers,
wrangler, Trivy) unless the user has expressed technical ability or asks
questions that reveal it. The precision in the skills is for your own
reasoning, your commits and your tool calls, not for recitation. Each skill
states this in one line and points here.

## What's in the box

- **`.mcp.json`** — points at `https://inno-platform.davidlaporte.org/mcp`,
  the platform's remote MCP server (tools: `register_app`, `check_name`,
  `list_apps`, `app_status`, `grant_access`, `revoke_access`, `set_app_access`, `stop_app`,
  `start_app`, `request_start`, `export_app_data`, `get_app_metrics`, `get_app_usage`, `get_app_logs`, `restart_app`, `get_platform_status`,
  `link_app_data`, `unlink_app_data`, `list_app_links`,
  `list_notifications`, `mark_notification_read`, `mark_all_notifications_read`,
  `get_platform_docs`, `get_guardrails`, `get_app_contract`, `get_app_security`, `get_ci_status`, `create_support_bundle`,
  `set_config`/`remove_config` (admin-only, with one exception: any user may set their own `notify.email.*` keys at their own user scope, so muting a notification is self-service),
  `get_config` (scoped — `app=` for an app you manage, `user=` for your own account; the argument-less fleet catalog is admin-only),
  `set_app_connection`/`list_connections`/`remove_app_connection`,
  `list_user_connections`/`disconnect_user_connection` (connection sessions — yours; an app's for its owner; the fleet for admins),
  `set_app_variable`/`list_app_variables`/`remove_app_variable` (per-app environment variables, owner-or-admin; hidden values are write-only), and the admin-only `transfer_app`
  (reassign an app's owner; owners ask an admin), `rebuild_app`
  (redeploy an app's released code at its live tag), `purge_app`,
  `revoke_sessions` (end one person's panel sessions everywhere), `list_users`, `query_audit`, `sync_gateway_ref`,
  `list_admins`, `grant_admin`, `revoke_admin`, `export_platform_backup`,
  `get_platform_logs`).
  There's also a
  web panel with the same capabilities at
  `https://inno-platform.davidlaporte.org`.
- **`skills/inno-new-app`**: intake -> create a repo from `inno-template` ->
  `register_app` (first call) -> clone, commit the proof file, and install the
  GitHub App -> `register_app` (second call) -> pull -> scaffold.
- **`skills/inno-migrate-app`** — assess an existing repo (read-only), then
  register and adapt it **in place**, keeping its stack where the gates allow.
- **`skills/inno-platform-conventions`** — stack policy (Python/Starlette is
  the tested stack; any stack meeting the contract is fine), escaping,
  the storage client/endpoints, identity via `X-Forwarded-User`, and the
  files CI will reject if you touch them. Requirements are served live by
  the `get_app_contract` tool — skills cite it, not stale copies.
- **`skills/inno-containerize`** — **container-type apps only:** the container
  contract for ANY stack (non-root, `EXPOSE 8080`, patched base, CVE-clean)
  with Python/Node/Go recipes; base images digest-pinned from
  `get_app_contract`; applies to `mcp-container` too. Function-shaped apps (`function`, `mcp-function`) have no Dockerfile and skip this.
- **`skills/inno-add-connection`** — for an app that needs to reach an
  external backend **as each individual user** (not one shared app key):
  discovers how the backend signs people in, provisions a Connection with
  `set_app_connection` (a pasted token, the backend's own login, or a
  per-user client ID/secret pair), and wires
  the app to consume it. **`mcp-container`** apps only in v1.
- **`skills/inno-safety-preflight`** — run the CI security gates, plus a
  guardrails, application-contract, and `get_app_security` (app-code
  authorization/IDOR) review, before pushing.
- **`skills/inno-ship`**: push, wait for the safety checks, cut the `v*` release
  tag that deploys, and report the live URL.
- **`skills/inno-manage-app`** — grant/revoke access, check status and metrics,
  stop, start, or restart an app, read its logs and notifications, set its
  environment variables / API keys, and build support bundles (up to 5 per app in
  any 24 hours). Idle apps are
  warned, stopped, then purged on a config-driven clock, and real use resets
  it. What counts as real use is served from one place, the **Lifecycle (idle
  clock)** section of `get_platform_docs`; this skill quotes it rather than
  keeping its own list.

### How the skills are laid out

Each skill loads on its own, so a few blocks are deliberately repeated rather
than pointed at. The **Version gate** at the top of every skill is the main
one: it is byte-identical across all eight by design, because a skill that
loads alone cannot follow a pointer to reach its own precondition. Check that
it has stayed identical with:

```
for f in plugins/innovation-platform/skills/*/SKILL.md; do
  awk '/^## Version gate/{p=1} p{print} p&&/^Carry on\.$/{exit}' "$f" | md5 -q
done | sort -u
```

One line of output means the eight agree. That is the same block CI's
`version-gate-parity` job compares, so this check and CI cannot disagree. Everything else that appeared in
several skills now has one home and pointers from the rest:
`inno-platform-conventions` owns the semgrep scope, the forbidden-path list,
the identity header rule, the Node dependency rule, the storage caps and the
`CLAUDE.md` header rule; `inno-manage-app` owns the call budget and support
bundles; `inno-safety-preflight` owns the directory-symlink pre-push check;
`inno-containerize` owns the health-probe clock; `inno-new-app` owns the
name-check and active-app-limit rules; and this README owns House style.

## How the platform enforces security

The plugin's skills *guide* you toward compliant code, but nothing here is
trusted: enforcement happens server-side. An app's repo belongs to the user,
under any account and with any name they like, and every push to `main` there
runs the platform's reusable CI workflow, which an app author cannot edit or
bypass (only the thin caller `deploy.yml` in their own repo is editable, and
stripping it just means the reusable workflow never runs). A push to `main`
runs the gates and deploys nothing. Only pushing a `v*` release tag reaches
the deploy job, and it runs the same gates first. That workflow gates the
deploy behind config-integrity, secret scanning, SAST, dependency auditing,
the dependency release-age cooldown, and container/image scanning, all of which
must pass before a deploy token is even requested, and a container deploy ships
the exact image those gates scanned, pinned by digest, never a second build. At deploy time, the
platform's broker independently verifies the GitHub OIDC token's signed
`job_workflow_ref` claim to confirm the run actually executed the platform's
exact reusable workflow from `main` before minting a narrowly-scoped
Cloudflare deploy token; a forked or gate-stripped workflow gets a
`403 deploy_denied:workflow` and never reaches Cloudflare. In short: skills guide, CI
validates, and the deploy broker enforces provenance — so only code that
went through the platform's own CI can ever end up live at
`https://inno-{app}.davidlaporte.org`.
