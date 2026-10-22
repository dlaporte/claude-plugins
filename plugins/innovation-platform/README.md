# innovation-platform

Claude Code plugin for your organization's Innovation Platform. It works with
any instance: every instance-specific value (hostnames, group names, the
template repo, the CI workflow, the Connections callback) is read from the
platform's `get_platform_status` tool, never written into a skill. Bundles the
`inno-platform` MCP server and nine skills: eight walk Claude through the
whole app lifecycle (create or migrate existing code, write, containerize,
connect to a per-user backend, gate-check, ship, and manage), and one serves
the platform's admins. Apps deploy as
one of four **types**, all behind the platform's front door, which signs
people in and decides who reaches each app: a **container** (any stack, a
Dockerfile, and the type `register_app` defaults to when none is given), a
**function** (its own Cloudflare Worker, JS/TS), an **mcp-function** app (an
MCP server in its own Cloudflare Worker, reached with an OAuth token the
platform issues unless the app is public), or an **mcp-container** app (an
MCP server in a Docker container, any language, reached the same way). The
type is chosen at
`register_app`.

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
This is expected: the MCP server authenticates you as yourself, so every
action it takes (creating an app, granting access, stopping or starting one)
is attributable to your real Okta identity, not a shared service credential.
**If the connector was NOT already authorized when your Claude Code session
started, authorizing it mid-session (e.g. via `/mcp`) is not enough**: the
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

If `get_platform_status` fails with an error about its output schema right
after a platform upgrade, the session listed the platform's tools before the
upgrade, and a client that checks answers against the schema it listed (the
MCP SDK client does) refuses the new answer. Platform v0.16.18's trim of the
status's `instance` block was the first such change. Reconnect (in Claude
Code, `/mcp`, then Reconnect) or start a new session, then run the skill
again.

Platform v0.17.0 made another: its status no longer carries a sign-out
address or gateway capabilities, and the admin tool that promoted the
gateway went with it, so reconnect after that upgrade too. Plugin 3.0.0
follows v0.17.0 and contract 34, where the platform signs people in to
browser apps itself and every app's sign-out link is `/_auth/signout`; the
platform asks for at least 3.0.0 when the instance's admins raise
`plugin.min_version`, as the v0.17.0 release asks.

Plugin 4.0.0 follows platform v0.17.2 and contract 35, which give every app
two properties: its **audience** (who may reach it: members-only, internal,
which is everyone who signs in and was called open before, or public, anyone
on the internet with no sign-in), changed at any time and widened only
through the plugin's review and a recorded guardrails acceptance; and its
**identity** (identity-aware or anonymous, whether the app is told who calls),
chosen at registration and fixed. Only an anonymous app can be public. Three
tools take new input (`set_app_access` takes `audience` and
`accept_guardrails` in place of `open`, `register_app` takes `identity`,
`transfer_app` takes `also` and `accept_guardrails`), and `app_status` and
`get_platform_status` answer in a new shape, so reconnect after that upgrade
too. Every skill learned the two properties: the identity question and the
two-app pattern for a public site at design time, the widening review and
the narrowing note, the contract's new R10 for anonymous apps with its
cookie rule, the uploaded-file rule, the front door's refusal, on a
members-only or internal app, of any request from another page that is not
a top-level GET navigation (so apps never
frame, include or call each other from the browser, and a data link is the
path between apps), the review of an app for every audience it can take,
and, for admins, allowing public apps, narrowing one in an emergency and
moving a linked pair together. The platform asks for at least
4.0.0 once the instance's admins raise `plugin.min_version`, as the v0.17.2
release asks.

Plugin 4.1.0 follows platform v0.17.3 and contract 36. No tool takes new
input, but `get_platform_status` no longer reports a membership authority,
so reconnect after that upgrade too. The skills follow what the release
changed: a purge takes a stopped app only, so an admin's fast takedown of a
public app is a stop, then a purge; a function app that still holds a
revoked data link's binding counts for `grant_access`, which refuses
`link_containment` until it is redeployed, and for `revoke_access`, which
rebuilds it; a locked backend credential has its own `connection_locked`
notice and email setting, and `connection_expired` means removed again;
app names may end in `-app`; the refusal codes renamed or added
(`link_containment` on `link_app_data`, `encryption_key_missing` and
`encryption_key_invalid`, `invalid_connection_name` and
`invalid_connection_definition`, `purge_app`'s `app_not_stopped` and
`r2_budget_exhausted`, `rebuild_app`'s `dispatch_in_flight`); numeric
settings refused outside their range; the retired `## Worker contract`
heading no longer passing the `CLAUDE.md` check; and the dependency gate
refusing a function app's `app/package.json` with no lockfile. The release
also corrected guidance that did harm when followed: the Dockerfile recipes
put comments after instructions, which breaks the build, so every comment
now sits on a line of its own; caching a backend credential is
`get_app_security` §8's rule, keyed so one person's credential never serves
another; and `inno-ship` gained rows for a superseded deploy
(`deployment_not_completable`, which must not be re-run blindly) and for
the deploy refusals it lacked. The platform asks for at least 4.1.0 once
the instance's admins raise `plugin.min_version`, as the v0.17.3 release
asks.

Plugin 4.1.1 follows platform v0.17.4, still contract 36. No tool takes new
input. A container app's release run now fails at its `container` job when
the upload that records the scanned image fails (`SBOM upload failed`, with
the platform's answer), and the platform refuses the deploy of a run that
recorded no image (`image_not_recorded`) before it mints or starts
anything; `inno-ship`'s rows tell an image too large for the platform from
an outage, and say where a stopped, mismatched or unlinked app's release
now fails. The first start of an app after a vulnerability finding uses no
self-service start, a start holds off the safety sweep for a while, and
`start_app`'s answer gives the time by which the fix must ship;
`inno-manage-app` relays it. A forced `transfer_app` rebuilds
function-shaped consumers only, since a container-shaped consumer's host
refuses the revoked link live. The v0.17.4 release does not raise the
floor: 4.1.0's rows misdiagnose a rare failure without breaking a build.

Plugin 4.2.0 follows platform v0.17.5 and contract 37. No tool takes new
input, but `app_status` and `get_platform_status` answer in a new shape, so
reconnect after that upgrade too. From this version the Version gate says
so itself. When its `get_platform_status` call fails with a validation or
schema error, it tells the user to reconnect the platform's server and
start the skill again (in Claude Code, `/mcp`, then Reconnect, or a new
session).

For members and owners, the skills follow what the release changed.
`app_status` lists the app's members, with the address a revoke takes. It
also names the revoked data links whose binding is still deployed, which
`list_app_links` lists too. When `revoke_access`'s cascade stops, its
warning names the redeploy, or an admin's `rebuild_app`, for each such
link. A `link_rebuild_pending` notice says that the code reading the
revoked source fails, and how to fix it. An instance whose manifest names a
support contact serves it on the status's `Support:` line. Each skill
that sends the user to a platform admin sends the request there, under
the rule `inno-manage-app` holds, and the platform's own refusals,
notices and sign-in pages name the contact too. The panel serves the
platform's user guide at `/guide`, for anyone signed in. A registered app
whose first deploy has not completed by the date `register_app`'s answer
gives is deleted, after a `first_deploy_due` reminder, and its name is
then free at once.
`inno-new-app` and `inno-migrate-app` pass that date on at the hand-off,
and say that the members named at registration are told when the app
first deploys.

For admins, `list_apps` marks each running app's health and every
vulnerable app, and `get_platform_status` names the apps behind its
UNHEALTHY and VULNERABLE counts. The audit reference reads the release's
three new rows: `app_signin_denied`, `connection_connect_failed` and
`app_first_deploy_due`.

The v0.17.5 release does not raise the floor: its output changes are
additive, and what 4.1.x lacks is guidance, not a step that breaks.

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
- **`skills/inno-migrate-app`**: assess an existing repo (read-only), then
  register and adapt it **in place**, keeping its stack where the gates allow.
- **`skills/inno-platform-conventions`**: stack policy (Python/Starlette is
  the tested stack; any stack meeting the contract is fine), escaping,
  the storage client/endpoints, identity (the kinds of caller the
  contract's R3 names, and the template's helper, which answers no user for
  a caller with no identity, says whether a caller is a member, and gives
  the `subject` to key per-person data on), the sign-out link, and the
  files CI will reject if you touch them. Requirements are served live by
  the `get_app_contract` tool, and the skills cite it rather than keeping
  copies.
- **`skills/inno-containerize`**: for **container-type apps only**, the container
  contract for ANY stack (non-root, `EXPOSE 8080`, patched base, CVE-clean)
  with Python/Node/Go recipes; base images digest-pinned from
  `get_app_contract`; applies to `mcp-container` too. Function-shaped apps (`function`, `mcp-function`) have no Dockerfile and skip this.
- **`skills/inno-add-connection`**: for an app that needs to reach an
  external backend **as each individual user** (not one shared app key):
  discovers how the backend signs people in, provisions a Connection with
  `set_app_connection` (a pasted token, the backend's own login, or a
  per-user client ID/secret pair), and wires
  the app to consume it. Identity-aware **`mcp-container`** apps only in
  v1.
- **`skills/inno-safety-preflight`**: run the CI security gates, plus a
  guardrails, application-contract, `get_app_security` (app-code
  authorization/IDOR) and `get_app_accessibility` (advisory) review, by
  pushing to the default branch, which runs the real gates and deploys
  nothing.
- **`skills/inno-ship`**: push, wait for the safety checks, cut the `v*` release
  tag that deploys, and report the live URL.
- **`skills/inno-manage-app`**: grant/revoke access, widen an app's audience
  through its review or narrow it, check status and metrics,
  stop, start, or restart an app, read its logs and notifications, set its
  environment variables / API keys, and build support bundles
  (`create_support_bundle`'s description gives the cap). Idle apps are
  warned, stopped, then purged on a config-driven clock, and real use resets
  it. What counts as real use is served from one place, the **Lifecycle (idle
  clock)** section of `get_platform_docs`; this skill quotes it rather than
  keeping its own list.
- **`skills/inno-fleet-admin`**: for platform admins only, the actions that
  reach across the fleet: the admin roster (`list_admins`, `grant_admin`,
  `revoke_admin`), filling an empty admin list from the Okta admin group
  (`import_okta_memberships`, its only job),
  reassigning an app's owner, purging an app, rebuilding an app's released
  code at its live tag (`rebuild_app`), ending one person's panel and browser
  app sessions everywhere, marking the instance's Okta admin group,
  accepting a naming change, platform configuration, and the fleet-wide
  reads (every app, every user, the audit log, the platform's logs and its
  backup). An owner manages their own apps with `inno-manage-app`.

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
`CLAUDE.md` header rule; `inno-new-app`'s
`references/hand-authored-layout.md` owns which `CLAUDE.md` to start from;
`inno-manage-app` owns the call budget (the CI poll cadence included),
support bundles, the active-app-limit rule, the transfer request, where a
request for a platform admin goes, and the
`cross_owner_link_revoked` and `host_upload_blocked` notices;
`inno-safety-preflight` owns the pre-push branch and symlink checks, how to
read `get_ci_status`, and how to read the CI accessibility, response-header
and Dockerfile reports; `inno-containerize` owns the health-probe clock;
`inno-new-app` owns the name-check rules; `inno-fleet-admin` owns the
admin-only actions (a purge's missing archive included); and this README
owns House style.

What the platform serves, the skills fetch rather than copy. The
application contract comes from `get_app_contract`: with no arguments it
serves the whole current contract, with `sections` only the numbered
sections named (for example `["2"]` for the requirements R1 to R10, or
`["2.2"]` for Connections), and with `history: true` the contract's version
notes alone, newest first. A contract or section answer opens with the
contract version and the current base images, so a narrow read never loses
them, and each skill asks only for the sections its step needs.

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
must pass before the deploy even starts. A container deploy ships the exact
image those gates scanned, pinned by digest, never a second build; a function
deploy ships the exact bundle CI built in a job that holds no credential of
any kind, and the deploy job checks it against that build's digest before it
requests any token. At deploy time, the platform's broker
independently verifies the GitHub OIDC token's signed `job_workflow_ref`
claim to confirm the run actually executed the platform's exact reusable
workflow from `main` before it accepts anything from the run. A function
app's run then holds no Cloudflare credential at all: the platform uploads
the app's Worker itself and sets every binding. A container app's run gets
only a narrowly scoped token to push its image, and the platform uploads its
host. A forked or gate-stripped workflow gets a `403 deploy_denied:workflow`
and never reaches Cloudflare. In short: skills guide, CI
validates, and the deploy broker enforces provenance, so only code that
went through the platform's own CI can ever end up live at
the app's own address (the platform reports the real hostname).
