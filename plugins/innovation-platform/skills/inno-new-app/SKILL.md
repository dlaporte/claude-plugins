---
name: inno-new-app
description: Use when the user wants to create a new app on the Innovation Platform ("new app", "create an app", "start a project on inno-platform"). Guides intake, creates a repo from the inno-template in the user's own account, calls register_app, commits the proof-of-control file it names and has them install the platform GitHub App, calls register_app again to provision + bind it, then scaffolds app/ per platform-conventions.
---

# inno-new-app

## Version gate — do this first

Before anything else in this skill, read the `version` field of
`../../.claude-plugin/plugin.json` (relative to this skill's own directory) and
pass it to the `get_platform_status` MCP tool as `plugin_version`.

The platform holds the minimum plugin version it accepts and does the
comparison. If the `Plugin:` line comes back **OUTDATED**, or says the version
was not reported or unreadable, STOP and tell the user to run:

```
claude plugin marketplace update davidlaporte
claude plugin update innovation-platform@davidlaporte
```

then restart Claude Code and start again. Do not continue on a stale plugin:
its guidance may describe platform behavior that no longer exists, and skills
added since their build are simply absent — this check is the only thing that
will tell them so.

If there is no `Plugin:` line at all, the gate is not armed on this platform.
Carry on.

Creates a new Innovation Platform app end to end: intake -> the user creates a
repo **they own** from the platform template -> `register_app` (first call)
-> commit the proof-of-control file it names + install the platform GitHub App
-> `register_app` (second call) provisions + binds it -> pull + scaffold. Requires the
`inno-platform` MCP server (ships with this plugin's `.mcp.json`) to be
connected. The first call to any `inno-platform` tool triggers an Okta browser
login — that's expected, not an error; wait for it to complete. **If the
connector wasn't already authorized when the session started, waiting isn't
enough** — mid-session authorization alone does not expose the tools (the MCP
client enumerates tools at startup); the user must authorize it AND you must
restart the session before calling any `inno-platform` tool.

**The repo is the USER's.** There is no platform-owned repo model anymore. The
repo lives in the user's **own** account or org, created from the public
`inno-template`, with the platform's GitHub App installed on it; `register_app`
finishes the job. The old `create_app` tool no longer exists, and the platform
never creates a `dlaporte/inno-{name}` repo on the user's behalf.

**What is genuinely user-only.** Exactly two steps in this flow require the user
personally: **installing the platform GitHub App** (§3 — a third-party token
cannot install a GitHub App on someone's account) and any **browser SSO login**.
Everything else (creating the repo, committing the registration proof file,
cloning, scaffolding, committing, pushing, tagging, setting variables) you can
do with the user's own authenticated CLI and MCP tools. Never tell the user something "can't be done from here" unless it
is one of those two. Where the reason is judgment rather than capability, say
which: setting a *secret* variable is a **should not** (it would put the secret
in the conversation transcript), not a **cannot**.

**Already have an existing repo?** If the user wants to put a repo/codebase they
*already* have on the platform (not create a fresh one from the template), use
the `inno-migrate-app` skill instead — it registers the existing repo in place
and adapts it to the contract, no scaffolding-from-template.

**Speak the user's language.** The platform serves a broad userbase including
non-technical users. When explaining anything to the user, use plain terms —
"a database", "file storage", "an access group", "your app's address",
"sign-in" — and do NOT name specific technologies or providers (Cloudflare,
D1, R2, Okta, Workers, wrangler) unless the user has expressed technical
ability or asks questions that reveal it. Full precision belongs in the code
and commits you write, not in explanations; this rule applies to every
user-facing sentence in this flow.

## 1. Intake — ask the user for five things

1. **App name** — lowercase letters, digits, hyphens only, 3-29 chars,
   starting with a letter. This drives the app's **hostname** on the platform
   domain (`inno-{name}.<domain>`), so keep it short and DNS-safe. It is NOT
   the repo name — the repo name is the user's choice (see below). A handful of
   names are reserved server-side — `check_name` reports those, so don't
   enumerate or guess. A name ending in **`-app`** is rejected as well: the
   server returns `invalid_name` for `todo-app`, so propose `todo` instead.
   Steer the user off that suffix before you check the name.

   **Verify availability before you settle on a name — never recommend or
   confirm a name without checking it first.** Call the **`check_name`** MCP
   tool (read-only; provisions nothing) on the candidate. Only proceed with a
   name it reports as **available**. If it comes back in-use, reserved, or
   invalid, ask the user for a different one. If it says the name **was
   recently purged and is held until** a UTC time, it belonged to an app purged
   within the last seven days and nobody, admins included, can register it
   before then (`register_app` refuses it as `name_quarantined`): offer a
   different name or wait. If it's the caller's *own*
   existing app, tell them that (a stopped app is brought back with
   `start_app`, not by re-registering it). `list_apps` shows the caller's own
   apps, and every app on the platform only when the caller is a platform
   admin. For an ordinary user it therefore cannot prove a name is free
   platform-wide: use `check_name`.

   **Active-app limit.** `check_name` also warns when the user is at their
   active-app limit ("you are at your active-app limit (N of M)") — at the cap,
   `register_app` WILL fail with `app_limit_reached`, so resolve this BEFORE any
   build work: show the user their apps (`list_apps`) and **offer to stop one or
   more** (`stop_app`) to make room — only ever with their explicit
   confirmation, never silently (stopping detaches the app's domain and starts
   its purge countdown). If they decline, stop here: the remaining options are
   asking a platform admin to raise their limit (`apps.max_active`, user scope)
   or not building the app.
2. **Repo** — the `owner/repo` slug of the GitHub repo the user will create
   from the template (§2). The **owner is the user's** account or org, and the
   repo name is **their choice** — suggest `inno-{name}` for familiarity, but it
   is not required and can be anything. The repo may be public or private.
3. **One-line purpose**: becomes the app's `description` (at most 500
   characters; the tool schema rejects a longer one).
4. **Initial members' emails** (optional, can be empty) — Okta emails to grant
   access alongside the owner. The list can be added to later with the
   `inno-manage-app` skill's `grant_access`.
5. **Does the app need to reach another service *as each person using it*?**
   Not the app's own sign-in (every app gets that for free) — this is about
   your app calling out to some *other* system that also tells its own users
   apart (a departmental system, a niche tool, a per-user account on some
   outside service). If yes, note it now: today that only works for an MCP
   server built the container way (affects the type choice in §1b below), and
   once the app is registered you'll set it up with the `inno-add-connection`
   skill.

## 1a. Guardrails check — HARD STOP on conflict

Before confirming anything, call the **`get_guardrails`** MCP tool and evaluate
the proposed **name** and **purpose** against the platform's acceptable-use
policy. This is qualitative judgment (impersonation, misleading authority,
offensive names, prohibited purposes, data handling) — apply the policy's
spirit, not just its examples. `register_app` requires you to pass
`accept_guardrails: true`, which asserts the app will follow these guardrails —
do not pass it until you've actually done this review.

- **Clean** → proceed; no need to mention it unless the user asks.
- **Conflict** → do NOT call `register_app`. Name the specific policy line,
  explain the problem in one plain sentence, and help the user pick a compliant
  name/purpose. If they believe their use is legitimate anyway (e.g. sanctioned
  research), direct them to a platform admin for an explicit exception first —
  you cannot grant one, and you must not register the app without it.

Confirm the name, repo, purpose, and members back to the user before going
further — registration provisions real resources (an access group, a database,
and file storage) and binds them to the user's repo.

## 1b. Design the app before registering

Before registering, produce and present a real design. The approval gate at the
end of this section is a hard one — `register_app` provisions real resources.

**Fetch the `get_app_contract` MCP tool first** — it carries the four deployment
**types** and their requirement deltas (§1.1–§1.3), the deployment patterns (and what
the platform does NOT support: background jobs, machine-to-machine APIs,
guaranteed long-lived connections), the stack policy, and the current
recommended base images. Evaluate the user's idea against it before designing; a
not-supported requirement surfaces HERE, not after registration.

Invoke the **`superpowers:brainstorming`** skill to design the app: what it does,
its data model (what it stores — tables, files), its routes/pages, and its
access model (who can see and edit). If that skill isn't available in the
session, run an equivalent inline pass over the same points yourself. Either
way, the design still has to be written into your reply and approved — see
"Present the design, THEN ask for approval" below; the skill's absence is not a
reason to skip that.

The design includes three contract-informed choices that are **the user's to
make, with your recommendation**:

- **Deployment type** — `function`, `container`, `mcp-function`, or
  `mcp-container` (passed to `register_app`; default container server-side,
  but for a **greenfield** app you recommend and default to **`function`** — or
  **`mcp-function`**/**`mcp-container`** when the product is an MCP server).
  `function` and `mcp-function` were formerly named `worker` and `mcp-worker`;
  the cutover is hard, so pass only the four names above. `type` is a schema
  enum, so on the MCP surface a retired name never reaches the tool: it fails
  argument validation with a plain enum error that does not name the
  replacement. The four types:

  - **`function` (recommend for greenfield):** the app is its own Cloudflare
    Worker (JS/TS) behind the gateway — ms cold starts, no Dockerfile,
    Workers-native bindings. This is the right fit for the common citizen-dev
    shape (a small web UI + JSON API in TS/JS).
  - **`container`:** choose this when the description gives a **clear signal**
    for it — an explicit **non-TS/JS stack** (Python, Go, Ruby, …), **native
    dependencies** or system binaries, **long-running / heavy compute**, or a
    port of existing non-JS code (that's `inno-migrate-app`, which defaults to
    container). Absent such a signal, prefer function.
  - **`mcp-function` (named `mcp` before v0.8.0):** choose when the product is an **MCP server for AI assistants**
    (Claude Code, claude.ai) rather than a browser UI. Function-shaped (JS/TS,
    no Dockerfile): the app serves the MCP **Streamable HTTP** transport at
    `POST /mcp`, and users add `https://inno-{name}.<domain>/mcp` as an MCP
    server in their client. **Stateless only** — tools work normally, but
    server-initiated features (notifications, sampling, elicitation,
    long-lived subscriptions) do not; if the design needs those, it does not
    fit this type today — surface that HERE, not after registration. Access
    is the same Okta member group as the other types (`grant_access` etc.);
    there is no browser SSO — the platform issues OAuth tokens and the
    gateway validates them (`get_app_contract` §1.2). **One hard constraint:**
    if §1 flagged that the app must reach another service *as each person using
    it* (a per-user **Connection**), this type **cannot** — only
    `mcp-container` can consume a Connection in v1. Choose `mcp-container`
    instead; do not land such an app on `mcp-function` and discover the gap
    after registration (the type is fixed at registration).
  - **`mcp-container`:** choose when the product is an **MCP server** that
    needs the **container** shape instead — a **non-TS/JS stack** (Python,
    Go, Ruby, …), **native dependencies**, **heavy/long-running compute**
    a Cloudflare Worker can't give it, **or an MCP server that must consume a
    per-user Connection** (this is the only type that can, in v1 — see
    `inno-add-connection`). Same MCP contract as `mcp-function` (Streamable
    HTTP at `POST /mcp`, **stateless only** — no notifications, sampling,
    elicitation, or long-lived subscriptions) layered on the container
    baseline: a Dockerfile serving `0.0.0.0:8080`, non-root `USER`, and
    `GET /healthz` (`get_app_contract` §1.3). Same OAuth perimeter and access
    story as `mcp-function` — no browser SSO, the platform issues OAuth tokens
    and the gateway validates them; access is still the app's Okta member
    group. Default stack: **Python + the official MCP Python SDK** (FastMCP).
    CRITICAL (Python SDK): construct FastMCP with
    `transport_security=TransportSecuritySettings(enable_dns_rebinding_protection=False)`
    (import from `mcp.server.transport_security`) — FastMCP otherwise auto-enables
    localhost-only Host validation (its `host` setting defaults to 127.0.0.1 even when
    uvicorn binds 0.0.0.0) and every gateway-forwarded /mcp request dies with
    `421 Invalid Host header`. The platform gateway is the identity boundary; rebinding
    protection only misfires behind it. Also: after deploying a fix to a RUNNING
    mcp-container app, `restart_app` — a live instance keeps serving the old image
    until it recycles.
    Note the idle **cold start**: a sleeping container wakes on request, so
    expect a seconds-scale delay on the first `POST /mcp` after idle
    (`sleep_after` default 10m) — mention this if responsiveness matters to
    the user.
  - State your recommendation and the reason, and go with the user's call.
- **Deployment pattern** (contract §5): server-rendered is the default for
  internal tools; SPA+API when rich client interactivity is the point — applies
  to either type.
- **Stack** — follows from the type: a **function** or **mcp-function** app is TS/JS
  (that is what Cloudflare Workers run; an mcp-function app builds on the MCP TypeScript SDK). A
  **container** app defaults to Python/Starlette (the tested
  container stack, with a working reference app), or the user's chosen stack —
  any language is supported; the container contract is HTTP on port 8080, not a
  language. An **mcp-container** app defaults to **Python + the official MCP
  Python SDK** (FastMCP) — but any language is equally supported, same
  contract.

### Present the design, THEN ask for approval

The user deserves to see what they're approving. **Write the full design into
your visible reply as a structured section — never a one-line summary buried
inside a tool-approval prompt.** An approval question that references "the
design as described" when no design appears in the conversation is a defect,
not a shortcut: the user cannot approve what they have not seen.

The written design covers, at minimum:

- **What the app does** — in the user's own terms, a short paragraph
- **Deployment type** and why (and the Connection constraint if §1 flagged it)
- **Data model** — the tables and files it will store
- **Routes / pages** — what the user can actually open and do
- **Access model**: who can see what, and who can edit. The platform manages
  only membership: `X-Forwarded-Groups` carries at most this app's own
  `inno-{name}-users` (a member) and `inno-{name}-open` (a caller who reached an
  open app), never the platform admin group or any other app's groups (for an
  SSO app from its first deploy on the v0.14.3 gateway onward; MCP apps get the
  narrowed header immediately). Any
  finer role (an editor, an admin view) needs the app's own role table keyed on
  `X-Forwarded-User`; do not design around reading other groups from the header.
- **Deployment pattern and stack**
- **Name** (confirmed available via `check_name`) and the exact hostname it
  produces
- **Initial members**, if any

Only after that design is in your reply: **stop and get explicit user
approval** (of the design *and* the name) before §2. Ask the approval question
in your own words referencing the design the user can now read; put genuinely
separate decisions (name choice, deployment type, members) in their own
questions rather than folding them into the approval. Registration provisions
real resources — an Okta access group, a database, and file storage — and binds
them to the user's repo; the type is fixed at registration.

The type and design seed the scaffolding in §4.

## 2. Create the repo from the template

The repo must land in the **user's own** ownership — the platform has no
create-on-behalf path and never creates a repo itself. That constrains *whose
account* it lands in, not *who runs the command*.

**Preferred: do it for them with `gh`.** Run `gh auth status`; an authenticated
account with `repo` scope is the user's **own** credential, so a repo it creates
lands in their ownership exactly as the browser path does. Confirm the name and
visibility with them, then:

```sh
gh repo create {owner}/{repo} --template dlaporte/inno-template --private
```

- Suggest `inno-{name}`; public or private is fine — check an existing `inno-*`
  repo of theirs (`gh repo view … --json isPrivate`) and match it rather than
  assuming.
- Template copying is **asynchronous**: an immediate `git clone` can land an
  empty repo. Poll `git fetch` until `origin/main` exists before checking out.

**Fallback: walk them through the browser** — when `gh` is absent or
unauthenticated, the account it holds is not theirs, or they simply prefer it:

1. Open **`https://github.com/dlaporte/inno-template/generate`** — GitHub's
   "Use this template" page for the public `inno-template`. (You can also reach
   it from the template repo's green **"Use this template" → "Create a new
   repository"** button.)
2. Set the **owner** to their own account or org, and the **repository name** to
   their choice (suggest `inno-{name}`). Public or private is fine.
3. Click **Create repository**. The repo lands in **their** ownership, already
   scaffolded from the template.

Note the resulting `owner/repo` slug — that's the `repo` argument for
`register_app`.

## 3. Register the app (two calls)

`register_app` is a **two-step** flow with two things in between: committing a
proof-of-control file to the repo, and the App install. Call it, commit the
proof file it names, give the user the install link, wait for them to install,
then call it again.

### Call 1: start registration, commit the proof file, get the install link

```
register_app({ app, repo, description, type, members, accept_guardrails: true, connections })
```

- `app` — the app name from §1 (drives the hostname). The wire parameter is
  `app`; no tool names the target app `name`. Every tool takes the app as
  `app`: the two variable tools, `set_app_variable` and `remove_app_variable`,
  use `name` for the *variable's* name, not the app.
- `repo` — the `owner/repo` slug from §2 (a **slug, not a URL**). `app` and
  `repo` are the only two the schema requires; everything below is optional to
  the schema, though the handler still refuses the call without
  `accept_guardrails: true`.
- `type` — from the design decision (§1b): `"function"` for the greenfield
  default, `"container"` when the description warranted it, `"mcp-function"` for
  an MCP server, `"mcp-container"` for an MCP server that needs the container
  shape. Omit for container. The type is fixed at registration and can't be
  switched later (register a new app to change it).
- `accept_guardrails: true` — required; you must have done the §1a review.
- `members` — optional list of Okta emails.
- `connections` — optional list of names, when §1 step 5 flagged a per-user
  backend. Pass what you plan to set up; it **creates nothing** (a connection
  needs a strategy and config only `set_app_connection` can supply) and is
  echoed back in the response as a reminder to configure each one. A
  badly-shaped name is noted in the response and never fails the registration.

The first call returns text beginning **`Registration started for "{name}" ←
{repo}.`** It carries, in this order: (a) the template link again, in case the
repo doesn't exist yet; (b) a **proof-of-control file**: a `path:` under
`.inno-platform/` and the exact `contents:` (a 64-character hex string), with a
sample command; and (c) an **App install link**
(`https://github.com/apps/…/installations/new?state=…`).

**Commit the proof file first.** Installing the GitHub App proves the platform
can SEE the repo; this file proves the caller can CHANGE it, and nothing binds
until it checks out. Use the path and contents exactly as the response prints
them; never derive or shorten them. Commit it on the repository's **default
branch** (`main` for a template copy) and push:

```bash
git clone <the user's repo>   # skip if §2 already cloned it
cd <repo>
git fetch origin && git checkout main && git pull --ff-only   # fails until the template copy has landed: wait and retry
mkdir -p .inno-platform
printf '%s\n' '<contents from the response>' > '<path from the response>'
git add '<path from the response>'
git commit -m "platform registration proof"
git push origin HEAD
```

This is not a user-only step: do it with the user's own authenticated `git` or
`gh`. Only when you have no write credential for the repo, walk the user through
GitHub's web UI (**Add file** > **Create new file**, the exact path as the file
name, the exact contents, committed directly to the default branch).
Surrounding whitespace (such as the newline `printf` adds) is tolerated;
everything else must match exactly. Leave the file in place: call 2 re-checks it
immediately before provisioning. After that nothing reads it again, and keeping
it is harmless. The push may start a CI run in the repo; it deploys nothing (the
app isn't built yet), so there is nothing to act on in its result. Never commit
the proof on an empty clone (template copying is asynchronous, so
`git checkout main` fails until `origin/main` exists) and never force-push it:
a forced push over the template copy wipes the scaffold, and call 2 then has
nothing to prune.

**Then give the user the install link verbatim** and ask them to:

1. Open it, and **install the platform GitHub App** on the account/org that owns
   `repo`, granting it access to that repository (repo-only access is fine; they
   can scope it to just this repo). If the App is already installed there with
   access to this repo (including "All repositories"), they can skip the link:
   call 2 verifies access directly.
2. Save the configuration. GitHub redirects them to the platform's verification
   page, which says **Repository verified** once the App can reach the repo AND
   the proof file matches. If it says **Proof file not found**, the file is
   missing, on the wrong branch, or has the wrong contents: fix it, then reopen
   the link or simply run call 2 (it re-checks without the redirect). If it
   says **GitHub App installed** instead (GitHub's configure flow, for an
   account that already had the App), that page carries no registration: just
   run call 2.

The link expires in 24 hours. Re-running `register_app` while the registration
is still pending reuses it, with the same proof path; once it has expired, the
response names a NEW proof path, and that new file is the one to commit.

### Call 2: finish provisioning, get the deploy.yml

Once the proof file is pushed to the default branch AND the user confirms
they've installed the App (or the App already covered the repo), call
`register_app` **again with the same arguments**. This re-checks the proof file,
then finishes the job server-side (prunes the template scaffold to the chosen
type in a new commit on the repo's default branch, pushed via the
installation token, provisions the Okta group + D1 + R2, and binds the
repo). It returns text beginning **`App
"{name}" registered from {repo}`** and containing:

- `URL (after first deploy): https://inno-{name}.<platform domain>` — **quote
  this from the response, never construct it** (the platform domain is
  deployment-specific). For an **mcp-function** or **mcp-container** app the
  response surfaces the **MCP endpoint** (`…/mcp`) instead — same rule: quote
  it from the response. The
  URL 404s until the first successful `inno-ship`.
- A `.github/workflows/deploy.yml` — the thin caller workflow that wires the
  repo to the platform's reusable CI. **Overwrite the repo's copy with the
  snippet the response returned.** The template ships a `deploy.yml` too, but it
  carries no `with:` block at all, so the reusable workflow falls back to
  deriving the app name from the repository name with any `inno-` prefix
  removed. That derived name is asserted to the broker, which resolves the real
  app from the signed repository id and refuses the run with `app_mismatch` when
  the two disagree. The template's file therefore works only when the repo is
  named `{name}` or `inno-{name}`; any other name needs the returned snippet,
  which carries the explicit `with: app: {name}` input and is correct for any
  repo name, so write it in every case. This is a real step, not a hands-off
  one. Keep the
  `workflow_dispatch` trigger (the platform re-dispatches it for security
  respins). The snippet has no `secrets:` line, and the file must not gain one:
  `secrets: inherit` is a blocking finding for the `sast` gate, and the
  platform workflow needs no caller secrets.

### Reading register_app's responses — branch, don't assume

- **`Registration started …`** on call 1: commit the proof file, hand over the
  install link, and wait (above). The same text on call 2 means the platform
  still cannot see the repo through the App (not installed yet, installed
  without access to this repo, or a transient GitHub failure), or the 24-hour
  registration expired. Compare the proof `path:` with the one you committed:
  if it changed, commit the new file. Then have the user install the App on the
  repo (or widen its repository access) and call again.
- **`App "{name}" registered …`** — call 2 succeeded; proceed to §4.
- **`guardrails_not_accepted`** — you didn't pass `accept_guardrails: true`; do
  the §1a review, then pass it.
- **`invalid_name` / reserved** — the name broke the shape rule, hit a reserved
  word, or ended in `-app`; pick another (you should have caught this with
  `check_name`).
- **`name_unavailable`** — an app with that name already exists and is not the
  caller's own partial registration; pick another name.
- **`invalid_type`** — `type` was not one of the four preset names. On the MCP
  surface a retired name (`worker`, `mcp-worker`, `mcp`) fails schema validation
  before it ever gets this far.
- **`invalid_repo`** — `repo` wasn't a valid `owner/repo` slug (you passed a URL
  or a bare name); fix it.
- **`repo_control_unproven`**: the App can reach the repo, but the
  proof-of-control file is missing from its default branch or its contents
  don't match. The error text repeats the exact path and contents: commit that
  file (call 1 above) and call again. It can come back at call 2 even after the
  setup page said verified, because call 2 re-checks the file right before
  provisioning, so never delete it early.
- **`name_quarantined`**: the name belonged to an app purged within the last
  seven days and is held until the UTC time the message names. There is no
  admin bypass: pick another name (check it with `check_name`), or wait until
  that time.
- **`repo_unreachable`**: between verification and call 2 the platform GitHub
  App lost access to the repo. Have the user reinstall the App on the repo, then
  call again.
- **`repo_identity_changed`**: the repo was renamed, transferred to another
  account, or deleted and recreated after it was verified. Confirm the repo's
  current `owner/repo` slug with the user and call again with it; a new slug
  starts a fresh registration with a new proof file and a new install link
  (have the user open that link and save). The stale verification can keep
  answering this (or `Registration started …` for the new slug when the App
  was already installed) for up to about a day; if it repeats, tell the user
  registration can finish once that window passes rather than calling in a
  loop.
- **`invalid_member_email`**: one of `members` is not a plain email address.
  Fix or drop it and call again.
- **`upstream_error`** (could not re-check the repository with GitHub): a
  transient GitHub failure during call 2's re-check. Wait a moment and call
  again with the same arguments.
- **`too_many_members`** — `members` held more than 50 emails. Register with a
  shorter list and add the rest afterward with `grant_access`.
- **`app_limit_reached`** — the user is at their active-app limit; resolve per
  §1 (offer `stop_app` with confirmation, or an admin raises the limit).
- **`repo_already_registered`** — that GitHub repo is already bound to an app
  (one repo binds to at most one app). Use a different repo, or manage the
  existing app via `inno-manage-app`. (`repo_id_conflict` is the audit action
  the platform records for this refusal; callers never see it as an error code.)
- **`repo_owner_claimed`** — repositories under that GitHub account are already
  registered on the platform by someone else, and only that first user may bind
  more repos under it. The message names who holds it: ask them or a platform
  admin to register on the user's behalf, or use a repo under an account of
  the user's own. Platform admins bypass this check, so an admin can register
  under a shared-org account directly without going through the first user.
- **`repo_mismatch`** — a partially-finished registration exists for this name
  with a *different* repo; finish it with the original repo, or start over with
  a consistent `repo`.
- **`github_app_not_configured`** — the platform's GitHub App isn't set up on
  this deployment; nobody can register until an admin configures it.
- **Repo wasn't template-derived** (call 2's response reports something like
  "scaffold not applied" / the repo shows none of the type-specific scaffold
  described in §4 after call 2 finishes) — the user registered a repo that
  didn't come from §2's "Use this template" flow (a blank GitHub "New
  repository" is the common way this happens), so the server had nothing to
  prune. This is not an error to retry — treat it as the empty-repo path in
  §4 below.
- **`registration_disabled`** — an admin has turned off self-service
  registration; a platform admin must re-enable it (`registration.enabled`).
- Any other non-empty error — surface it verbatim rather than retrying blindly.

## 4. Pull and scaffold

You cloned the repo in §3 to commit the proof file. Call 2 then pushed the
platform's scaffold prune to the repo's default branch as a new commit from
the server side, so bring the clone up to date before touching anything (a
push from the stale clone would be rejected as non-fast-forward):

```bash
cd <repo>
git pull --ff-only   # picks up the registration's "scaffold: <type>" commit, if it applied one
```

If the proof file was committed through GitHub's web UI instead, clone now:
`git clone <the user's repo>` (e.g. `git@github.com:<owner>/<repo>.git`), then
`cd <repo>`.

After call 2, the repo has been **pruned to the deployment type you chose** —
the template carries every scaffold and the platform rewrote the repo at
registration. All types ship the thin `.github/workflows/deploy.yml` caller
workflow, which you overwrite with call 2's snippet per §3; a
**function** repo has the TS reference (`app/index.ts`),
an **mcp-function** repo the MCP-server TS reference (also `app/index.ts`), and
a **container** repo the Python/Starlette reference (`app/` — incl. `main.py`,
`storage.py`, `templates/`, `requirements.txt` — plus `Dockerfile` and `lib/`).
An **mcp-container** repo ships **its own overlay** (`scaffold/mcp-container/`,
platform v0.14.5): a stateless FastMCP starter for `app/main.py`, plus its own
`README.md`, `CLAUDE.md`, and `app/requirements.txt`, applied over the
container root (see the bullet below); `Dockerfile`, `lib/`, and
`app/storage.py` stay as the container reference's. Everything
else is platform-owned and must NOT be in the repo: all of a repo-root `src/`
(its gateway was bundled from there and the deploy wipes it, and the
`config-integrity` gate fails a repo carrying any file under it; an `app/src/`
of your own is fine), the
repo-root `package.json`, `package-lock.json` and `tsconfig.json`, any
`wrangler.*` config, and a `.npmrc` at any depth (including `app/.npmrc`).
Don't create any of them. Don't commit a symlink that points at a directory
anywhere in the repo either, dangling ones included (a link to a *file* is
fine): the `config-integrity` gate walks the tree without following links, so
it rejects every directory link outright, with no policy toggle. Load the
`inno-platform-conventions` skill before writing any application code (stack
policy, storage, identity, the do-not-touch file list), and — for a container
or mcp-container app — the `inno-containerize` skill before editing the
Dockerfile.

**If the repo wasn't template-derived, there's nothing to prune — author the
layout by hand.** A repo created via GitHub's blank "New repository" flow
(instead of §2's "Use this template") arrives with no scaffold, so call 2
leaves it as-is. Recognize this early — the repo is missing the type-specific
files described below — and hand-author the full layout out of `inno-template`,
then write `.github/workflows/deploy.yml` from call 2's response. Where you copy
from depends on the type, because three of the four have an overlay
directory:

- **`function` / `mcp-function`:** copy `scaffold/function/` or
  `scaffold/mcp-function/`. Each carries `CLAUDE.md`, `README.md`, and an
  `app/` (`index.ts`, plus `package.json` and its lockfile for
  `mcp-function`). Take `.gitignore` from the template root.
- **`mcp-container`:** copy `scaffold/mcp-container/` (platform v0.14.5):
  `CLAUDE.md`, `README.md`, `app/main.py`, and `app/requirements.txt`. Fill
  in the rest from the template root, which the overlay does not carry:
  `Dockerfile`, `.dockerignore`, `lib/`, `app/storage.py`, and `.gitignore`
  (skip `app/templates/`, which this type has no use for).
- **`container`:** there is no `scaffold/container/`, because the container
  files ARE the template root. Copy those: `Dockerfile`, `.dockerignore`,
  `lib/`, `app/main.py`, `app/storage.py`, `app/templates/`,
  `app/requirements.txt`, the root `CLAUDE.md`, `README.md`, and `.gitignore`.

Copy `CLAUDE.md` rather than writing one: the `config-integrity` gate checks
five required section headers. **The check is type-blind.** Three headers are
required of every app whatever its type: `## Innovation Platform App`,
`## Identity (do not build auth)`, and `## What CI enforces`. The remaining two
are variant groups, and any member of a group satisfies the gate:
`## Persistence (use the storage client)` or `## Persistence (use your
bindings)`, and `## Container contract` or `## Function contract` (the legacy
`## Worker contract` still passes too). So a container app carrying the
function headers passes and the reverse passes as well. Copy your own type's
version anyway, so the body describes the runtime this app actually has.

**Scaffold by the deployment type you chose in §1b** (fetch `get_app_contract`
§1.1 for the authoritative function deltas):

- **`function` app (greenfield default):** the entry is **`app/index.ts`**
  exporting `export default { fetch(request, env, ctx) }`. The request is
  already Access-verified — read identity from `request.headers`
  (`X-Forwarded-User` / `X-Forwarded-Groups`), serve **`GET /healthz` as a
  route** (200), and reach storage through the app's **own bindings** —
  `env.DATA` (D1), `env.FILES` (R2), not `storage.internal`. Declare every
  npm package the code imports in a **non-root** `app/package.json`, and commit
  the `app/package-lock.json` that `npm install` (run inside `app/`) produces,
  kept in sync with `package.json`. CI installs with
  `npm ci --ignore-scripts` inside `app/` in the `app-deps` job and fails
  without a lockfile or with a stale one; the deploy job runs no package
  manager in `app/`, and nothing is installed at the repo root, so an import
  not declared in `app/package.json` fails to bundle (for example
  `Could not resolve "hono"`). That install runs on **every push to the default
  branch** (platform v0.14.14), not only at the release tag, so a missing
  lockfile reds the preflight run. The `deps` gate is not what catches it: that
  audit generates a throwaway lockfile of its own. The repo is already function-shaped
  (no Dockerfile, no Python reference — the CI image gates are skipped for this
  type); extend `app/index.ts` rather than re-scaffolding. Never interpolate
  user data into hand-built HTML — even escaped, the SAST gate blocks it; return
  dynamic data as JSON (like the scaffold's `/me`) or use an auto-escaping
  template library. Do NOT create `wrangler.jsonc`/`app-worker.jsonc` — those
  are platform-injected. Include the required **sign-out link** (R4) — same as
  the container reference: a static link to the team-domain logout, its URL
  sourced from `get_platform_status`'s `Sign-out URL` (see
  `inno-platform-conventions`'s "Sign out" section for the exact convention);
  nothing in this type's scaffold provides it for you.
- **`mcp-function` app:** function-shaped — everything in the function bullet applies
  (entry `app/index.ts`, identity headers, `GET /healthz` as a route,
  `env.DATA`/`env.FILES`, non-root `app/package.json` with its committed
  `app/package-lock.json` kept in sync (the scaffold ships both), no injected
  files).
  Deltas (authoritative: `get_app_contract` §1.2): serve the MCP **Streamable
  HTTP** transport at `POST /mcp` using the MCP TypeScript SDK's
  `WebStandardStreamableHTTPServerTransport`, constructed **without a
  `sessionIdGenerator`** (stateless — every `POST /mcp` self-contained).
  Implement **no auth of any kind**: the platform is the OAuth Authorization
  Server and the gateway is the Resource Server — the `Authorization` header
  never reaches the app, and the `/.well-known/oauth-protected-resource`
  metadata is served by the platform; never route those paths yourself. No
  sign-out link (there is no browser session).
- **`container` app, tested stack (Python):** start from the reference app
  (`app/main.py` + `Dockerfile`) and extend it — don't regenerate from scratch.
- **`container` app, another stack:** replace `app/` and the `Dockerfile`
  wholesale for that stack, honoring the contract (port 8080, `/healthz`,
  identity headers, the `storage.internal` endpoints, sign-out link).
- **`mcp-container` app:** the template's `scaffold/mcp-container/` overlay
  (platform v0.14.5) ships a stateless FastMCP starter for this type, so
  pruning applies that overlay's `.scaffold-remove` (it deletes
  `app/templates/`, which this type has no use for) then moves the overlay's
  `app/main.py`, `README.md`, `CLAUDE.md`, and `app/requirements.txt` onto
  the container root; `Dockerfile`, `lib/`, and `app/storage.py` stay as the
  container reference's. `app/main.py` already speaks Streamable HTTP at
  `POST /mcp` with two example tools (`whoami`, `echo`) and already answers
  non-POST `/mcp` requests with 405: extend it rather than adapting a
  Starlette demo into an MCP server. `app/storage.py` carries the storage
  **and `Connections` helpers** your tools consume, see
  `inno-add-connection`. Contract (authoritative: `get_app_contract` §1.3):
  the container baseline (Dockerfile, `0.0.0.0:8080`, non-root `USER`,
  `GET /healthz`, storage via `http://storage.internal`) PLUS the MCP
  **Streamable HTTP** transport at `POST /mcp`, **stateless only** (no
  `sessionIdGenerator`/session correlation, same restriction as
  `mcp-function`). The starter already constructs FastMCP with
  `transport_security=TransportSecuritySettings(enable_dns_rebinding_protection=False)`;
  keep it that way. Removing it re-enables FastMCP's localhost-only Host
  check, and every gateway-forwarded `/mcp` request then fails with
  `421 Invalid Host header`, since the gateway proxies with this app's public
  Host header, not localhost. Identity: implement no auth of your own, the
  platform is the OAuth Authorization Server, the gateway is the Resource
  Server; read `X-Forwarded-User`/`X-Forwarded-Groups` only, and never route
  `/.well-known/oauth-protected-resource` yourself; no sign-out link (there
  is no browser session). Default stack: Python plus the official MCP Python
  SDK (FastMCP), pinned below `mcp` 2 in `app/requirements.txt` (2 renamed
  the `FastMCP` API the starter uses); build the container image per
  `inno-containerize`. Expect a seconds-scale cold start on the first
  request after the container has been idle (`sleep_after` default 10m).

**Delete the scaffold marker as you build.** The template repo ships
`app/.needs-build`, which makes CI skip deployment until it's removed. Once you
begin writing the real app (per the approved design), delete it:

```bash
rm -f app/.needs-build
```

Leaving it in place means `inno-ship` will refuse to deploy — by design.

Typical scaffolding steps for a new feature (Python **container** reference
shown; a **function** app does the equivalent inside `app/index.ts`'s `fetch`
handler — route on the URL, read identity from the request headers, read/write
`env.DATA`/`env.FILES`):
- Add routes to `app/main.py` (container) or `app/index.ts` (function); split into
  modules under `app/` as it grows.
- (Container, Python) add templates under `app/templates/` — never delete the
  directory while the reference Dockerfile is in use (a missing `templates/` is
  a common runtime 500, see `inno-containerize`).
- Add pinned dependencies to the stack's manifest (`app/requirements.txt` for
  the Python container; `app/package.json` for a function or a Node container).
  For a function or mcp-function app, also run `npm install` inside `app/` and
  commit the updated `app/package-lock.json` in the same commit (see the
  function bullet above).

**Rewrite `README.md` — this is required, not optional.** The template's README
is inno-template's own ("Use this template…", template internals) and describes
nothing about this app. Replace it with a **high-level overview of the user's
app**: what it does, who it's for, and the app's URL. Keep it short — a few
paragraphs is right; the platform mechanics (identity, storage, CI) already live
in `CLAUDE.md` and don't belong here. The README is the user's file from then
on: they can deepen it to whatever level of detail they prefer, and later
features should keep it truthful.

## 5. Hand off

Once scaffolding is in place, tell the user the app was registered (their repo +
future URL — for an **mcp-function** or **mcp-container** app, the `/mcp`
endpoint their MCP client will use), and that the next steps are: write the
app, run
`inno-safety-preflight` locally, then `inno-ship`. Beyond the registration
proof file (§3), don't push anything yet unless asked: `inno-new-app`'s job is
registration + scaffolding, not deploying.

If §1 flagged that the app needs to reach another service as each person using
it, do that setup now, before writing the rest of the app: run the
`inno-add-connection` skill (requires the `mcp-container` type from §1b).

If the app needs an app-level key or config value instead (one API key the
whole app shares, a base URL), set it after registration with
`set_app_variable` — it reaches the app as a plain environment variable.
Never put it in the repo; gitleaks fails the build on the full history.
