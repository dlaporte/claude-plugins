# innovation-platform

Claude Code plugin for your organization's Innovation Platform. It works with
any instance: every instance-specific value (hostnames, group names, the
template repo, the CI workflow, the Connections callback) is read from the
platform's `get_platform_status` tool, never written into a skill. Bundles the
`inno-platform` MCP server and nine skills: eight walk Claude through the
whole app lifecycle (create or migrate existing code, write, containerize,
connect to a per-user backend, gate-check, ship, and manage), and one serves
the platform's admins. Apps deploy as
one of four **types** behind the
same identity gateway: a **container** (any stack, a Dockerfile, and the type
`register_app` defaults to when none is given), a **function** (its own
Cloudflare Worker, JS/TS), an **mcp-function** app (an MCP server in its own
Cloudflare Worker behind the OAuth gateway), or an **mcp-container** app (an
MCP server in a Docker container, any language, behind the same OAuth
gateway). The type is chosen at `register_app`.

**Repos are user-owned.** An app is created by **registering a GitHub repo you
own**. You create a repo from the instance's public template repo ("Use this template" →
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
or private), and uninstalling the App unlinks and stops the app.

## Install

For a first install, take everything from your platform's panel: its
**Connect Claude Code** card gives the exact commands for your instance.
`<marketplace>`, `<marketplace source>` and the platform MCP address all come
from that card, because you are not connected yet and cannot read the status.
Copy the commands and run them in a terminal. They add the marketplace, then
install the plugin with your platform's address:

```
claude plugin marketplace add <marketplace source>
```

```
claude plugin install innovation-platform@<marketplace> --config platform_url=https://<platform host>/mcp
```

`platform_url` is the platform's MCP address (the `MCP address:` line of
`get_platform_status`, ending in `/mcp`). The plugin works with any instance:
the address is the only setting.

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
Either way the fix is the commands on the status's `Update commands:` line
that `get_platform_status` serves. The panel's Connect Claude Code card shows
the marketplace add, install, `mcp add` and configure commands, but not the
update commands. Update the marketplace, update the plugin, and restart Claude
Code.

An installed plugin is cached per version, so
without those commands nothing in Claude Code itself tells a user they are
on an old build; that `Plugin:` line is the only signal, and only a skill that
ran the gate has seen it.

### House style

Every skill in this plugin speaks to a broad, largely non-technical userbase,
so the sentences you say back to a user use plain terms: "access", "a
database", "file storage", "your app's address", "sign-in". Do **not** name
specific technologies or providers (Cloudflare, D1, R2, Okta, Workers,
wrangler, Trivy) unless the user has expressed technical ability or asks
questions that reveal it. The precision in the skills is for your own
reasoning, your commits and your tool calls, not for recitation. Each skill
that speaks to the user states this in one line and points here.
`inno-containerize` and `inno-platform-conventions` do not, because what they
produce is a Dockerfile and app code rather than sentences a user reads.

## What's in the box

- **`.mcp.json`**: points at the address you set as `platform_url`
  (the platform's MCP address), the platform's remote MCP server. Its tools
  are not listed here, because the platform is their one source: your MCP
  client lists them (`/mcp` in Claude Code), each tool's own description says
  what it does, who may call it and what it refuses (the refusals every tool
  shares are in the server's instructions), and `get_platform_status` serves
  your instance's own values. There's also a
  web panel with the same capabilities at
  the platform's address (the `Panel URL:` line of `get_platform_status`).
- **`skills/inno-new-app`**: intake -> create a repo from the template repo ->
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
  guardrails, application-contract, `get_app_security` (app-code
  authorization/IDOR) and `get_app_accessibility` (advisory) review, by
  pushing to the default branch, which runs the real gates and deploys
  nothing.
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
- **`skills/inno-fleet-admin`**: for platform admins only, the actions that
  reach across the fleet: the admin roster (`list_admins`, `grant_admin`,
  `revoke_admin`), comparing the platform's membership tables with Okta and
  closing the gaps (`import_okta_memberships`), reassigning an app's owner,
  purging an app, ending one person's panel sessions everywhere, claiming the
  instance's Okta groups, accepting a naming change, platform configuration,
  and the fleet-wide reads (every app, every user, the audit log, the
  platform's logs and its backup). An owner manages their own apps with
  `inno-manage-app`.

### How the skills are laid out

Each skill loads on its own, so a few blocks are deliberately repeated rather
than pointed at. The **Version gate** at the top of every skill is the main
one: it is byte-identical across all nine by design, because a skill that
loads alone cannot follow a pointer to reach its own precondition. Check that
it has stayed identical with:

```
for f in plugins/innovation-platform/skills/*/SKILL.md; do
  awk '/^## Version gate/{p=1} p{print} p&&/^Carry on\.$/{exit}' "$f" | md5 -q
done | sort -u
```

One line of output means the nine agree. That is the same block CI's
`version-gate-parity` job compares, so this check and CI cannot disagree. Everything else that appeared in
several skills now has one home and pointers from the rest:
`inno-platform-conventions` owns the semgrep scope, the forbidden-path list,
the identity header rule, the Node dependency rule, the storage caps and the
`CLAUDE.md` header rule; `inno-manage-app` owns the call budget, support
bundles and the active-app-limit rule; `inno-safety-preflight` owns the pre-push branch and
directory-symlink checks, how to read `get_ci_status`, and how to read the
CI accessibility, response-header and Dockerfile reports;
`inno-containerize` owns the health-probe clock; `inno-new-app` owns the
name-check rules; `inno-fleet-admin` owns the admin-only actions; and this
README owns House style.

## How the platform enforces security

The plugin's skills *guide* you toward compliant code, but nothing here is
trusted: enforcement happens server-side. An app's repo belongs to the user,
under any account and with any name they like, and every push to that repo's
default branch runs the platform's reusable CI workflow, which an app author cannot edit or
bypass (only the thin caller `deploy.yml` in their own repo is editable, and
stripping it just means the reusable workflow never runs). A push to the
default branch runs the gates and deploys nothing. Only pushing a `v*` release tag reaches
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
the app's own address (the platform reports the real hostname).
