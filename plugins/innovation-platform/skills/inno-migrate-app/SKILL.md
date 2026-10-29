---
name: inno-migrate-app
description: Use when the user has an EXISTING repo or codebase they want on the Innovation Platform ("deploy this to the innovation platform", "migrate this app", "put this repo on inno-platform"). Registers the user's existing repo in place via register_app and adapts it to the platform contract, with no copying into a new repo, keeping its stack where the gates allow.
---

# inno-migrate-app

## Version gate: do this first

Before anything else in this skill, do these six steps in order.

1. If no `inno-platform` tools are available at all, the platform address is
   probably unset. Tell the user to open their platform's panel, copy the
   configure command from its Connect Claude Code card, run it in a terminal,
   and restart Claude Code. Then STOP.
2. Read the `version` field of `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`
   and call the `get_platform_status` MCP tool with it as `plugin_version`.
3. If that call fails with an error (a validation or schema error, not one of
   the refusals the platform's instructions name), the session still holds
   the platform's tools from before an upgrade. Tell the user to reconnect
   the platform's server (in Claude Code, `/mcp`, then Reconnect, or start a
   new session), then start the skill again. Then STOP.
4. If the `Plugin:` line says `OUTDATED`, `version not reported`, or
   `reported version is not a MAJOR.MINOR.PATCH triple`, STOP. Tell the user
   to run the commands that line gives, then restart Claude Code and start
   again. Do not continue on a stale plugin: its guidance may describe
   platform behavior that no longer exists. If there is no `Plugin:` line at
   all, the platform sets no minimum version: go on to the next step.
5. If the `Plugin:` line says `current` and adds that a newer version
   `is available`, that is advice, not a block. Mention it once, with the
   commands from the `Update commands:` line, and go on to the next step.
6. If the status has no `Template repo:` line, the platform is older than
   v0.15.8. Say so, ask the user's admin to upgrade it, and STOP before any
   step that needs an instance value. Never fall back to a literal value.

Carry on.

An existing repo now deploys **in place**. You register the user's **own** repo
with the `register_app` MCP tool and make that same repo satisfy the platform
contract: there is no porting into a freshly provisioned repo and
no copying. The repo stays the user's, on their account/org, public or private.

This differs from `inno-new-app` only in the starting point: new-app has the
user create a fresh repo from the platform's template; here the user already has a repo.
If their repo is **already built to the platform contract** (app code under
`app/`, a `CLAUDE.md` with the required headers, `/healthz`, identity from the
front door's headers), migration is just: `register_app`, commit the proof file it
names, install the platform GitHub App on the repo, and `register_app` again. If it's an **arbitrary app** not written for the platform, you
assess it, then adapt it in place before shipping.

Requires the `inno-platform` MCP server (ships with this plugin). The first tool
call triggers a browser sign-in through your organization's identity
provider: expected, not an error.

**Asking a platform admin.** Where this skill sends the user to a platform
admin (a guardrails exception, a higher app limit, a fix on the platform's
side), the request goes to the contact the platform names: the `Support:`
line of the status you read in the Version gate, when it has one.
`inno-manage-app`'s **Asking a platform admin** is the one home for that
rule.

## Phase 1: Assess (read-only; register nothing yet)

**Fetch the contract first: it IS the assessment checklist.** Call the
`get_app_contract` MCP tool with
`sections: ["1", "1.1", "1.2", "1.3", "2", "3", "4", "4.1", "5"]`: the types
and their deltas, the requirements R1 to R10, the recommendations, the stack
policy, the base images,
and the deployment patterns with what the platform does NOT support
(background jobs, machine-to-machine APIs, guaranteed long-lived
connections: instant blockers to surface). Fetch `"2.2"` too when the repo
authenticates to a backend as each user (item 2), `"2.3"` when it reads
configuration from its environment or a `.env` file (item 5), and `"2.1"`
when it shares a database with another app of the user's (item 3), which on
the platform takes a data link. Judge the repo against the contract, not a
remembered summary of it.

If the app has pages people open in a browser, **fetch `get_app_accessibility`
beside it.** It serves the platform's accessibility notes (WCAG 2.2 AA as the
target; a school's own policy governs where it has one), and it is the
checklist for assessment item 8 below. Contract §3 recommends it rather than
requiring it, so a shortfall goes into the plan as work to do, never as a
blocker.

Scan the existing repo and present a **migration assessment** covering, in
order:

1. **Stack: keep vs. adapt is the user's decision, informed by your analysis.**
   Present findings to the user in plain language; the precision below is for
   your assessment, not recitation. The plugin README's **House style**
   section is the rule.

   The platform contract is **HTTP on port 8080** (container) or a Cloudflare
   Worker `fetch` handler (function), **not a language** (contract §4): no CI
   gate checks the language or framework. Keeping the existing stack
   (TypeScript/Express, Go, Ruby, Python, whatever) is usually the right call
   and the default bias. Present:
   - **Can the current stack meet R1 to R10?** Most stacks can, as-is; where
     one fails, it is at the container gate or the security gates (R8).
   - **Deployment type**: default **`container`** (keeps any stack). Only raise
     **`function`** when the source is already JS/TS and reimplementing it as a
     Cloudflare Worker is a deliberate choice the user opts into (closer to a
     rewrite; see `get_app_contract` §1.1). If the source is an **MCP server**,
     raise **`mcp-function`** for a TS/JS source (§1.2) or **`mcp-container`**
     for a Python/other-stack source (§1.3); both are stateless only.
     **Exception:** if the MCP source needs a per-user **Connection** to a
     backend (step 2 below), it MUST be `mcp-container` even when the source
     is TS/JS: `mcp-function` cannot consume a Connection in v1. CRITICAL for
     a Python source using FastMCP (the `mcp` SDK): it needs the
     `transport_security` setting `get_app_contract` §1.3 states, or every
     `/mcp` request the front door forwards fails. The contract is where that
     setting is written down; take it from there.
   - **Any deal-breakers?** A hard blocker that makes the platform unable to run
     the app at all: call it out plainly. Check the lockfile for the known
     friction §4 names, a framework whose pins drag in a CVE-bearing
     dependency (FastAPI's Starlette is its example).
   Note the entrypoint, framework, and listen port so you can adapt them to
   8080 + `/healthz`.
2. **Auth to strip**: login routes, session middleware, password storage, OAuth
   flows. All of it goes: the front door decides who reaches the app and
   tells it who the caller is, in `X-Forwarded-User` / `X-Forwarded-Groups` /
   `X-Forwarded-Subject` (see `inno-platform-conventions`). List each
   file/route to remove; an existing sign-out link becomes a plain link to
   `/_auth/signout` (R4), shown wherever the app shows who is signed in. Keep
   the app's own **authorization** (who may edit what), decided per request
   for each kind of caller contract R3 names (a member is only
   one of them, and a caller with no identity gets no per-person data or
   role), rewired to key on `X-Forwarded-Subject` (the person's identity
   provider ID, never the email address, which can change for one person
   and pass to another; rows the app already keys on an address may be
   re-keyed once, as contract §3 says):
   `X-Forwarded-Groups` carries only this app's members group, and only for
   a member (the name in the `App groups:` line of the status you read in
   the Version gate, with the app's name in place of `{app}`), never the
   repo's existing role groups,
   so existing role checks cannot move onto that header. The full header rule is
   `inno-platform-conventions`' **Identity** section. This is about the
   app's *own* sign-in for its users. A separate thing to look for is auth to a
   *backend the app calls out to*: if the repo runs its own OAuth flow
   against some other service, holds a long-lived per-user token for that
   service, or ships a sidecar
   whose whole job is minting/refreshing that credential, don't port any of
   it: that's exactly what a Connection replaces. Flag it in the assessment
   and point at the `inno-add-connection` skill for Phase 2 instead of
   carrying the old backend-auth code forward (note: needs the `mcp-container`
   type, per Phase 1 step 1's deployment-type bullet).
3. **Persistence to port**: local files and SQLite move to the platform's
   storage (D1 for SQL, R2 for files) reached at `http://storage.internal`
   (container) or the app's own `env.DATA`/`env.FILES` bindings (function).
   On the `storage.internal` path, R5 caps a SQL body and a file `PUT`, and
   refuses a `PUT` with no `Content-Length`, which is worth planning the port
   around: a one-shot import of an existing SQLite table has to go in
   batches. The codes and the reasoning are `inno-platform-conventions`'
   **Persistence** section. Neither cap applies on the bindings path.
   Dependencies the platform cannot provide (Postgres-specific SQL, Redis,
   queues, third-party managed services) are **blockers**: name them, never
   silently drop them.
4. **Contract deltas**: listens on 8080, serves `/healthz`, runs non-root,
   patched base image (container; see `inno-containerize`); app code arranged
   under `app/`; a root `CLAUDE.md` carrying the platform's required section
   headers (config-integrity checks them; which guide to start from, and how
   to merge it into a `CLAUDE.md` the repo already has, is `inno-new-app`'s
   `references/hand-authored-layout.md`). The repo's **default branch** needs no
   special handling: registration's scaffold prune and the `deploy.yml` that
   `register_app` returns both target the repo's actual default branch,
   whatever it is named, and `inno-safety-preflight` and
   `inno-ship` push to that same branch.
5. **Gate risks**: secrets **anywhere in git history** (gitleaks scans the full
   history, and this is the *same* repo: history is not left behind, so a
   secret buried in an old commit still fails: rotate it first, then either
   remove it from the history or record its finding's fingerprint in
   `.gitleaksignore`, as `inno-ship`'s `secrets` row says, and never delete
   the file in a new commit, which leaves the secret in the old one; the
   rotated value then goes into an app Variable, never back in the repo),
   dependency CVEs (`pip-audit`, Trivy), and semgrep OWASP patterns such as
   string-built HTML or raw SQL formatting. **Semgrep scans the whole
   repository, not just `app/`**: root-level scripts, tools, workflow files
   and the Dockerfile all count, so a migrated repo's non-app files can fail
   the gate too. R8 states the exact scope, and what it skips. Then list every path
   the `config-integrity` gate rejects. That list has one home too,
   `inno-platform-conventions`' **Files you must not touch** section; walk it
   against this repo and note every hit. The three that catch migrated repos
   most often:
   - **anything under a repo-root `src/`**, which a repo whose code lives
     there must move, for example to `app/src/` (updating the Dockerfile's
     `COPY` paths);
   - the repo-root `package.json`, `package-lock.json` and `tsconfig.json`,
     which in a Node repo are often the app's real manifests rather than
     leftovers, so show them to the user before touching them;
   - **any committed symlink that resolves to a directory, or to a file
     outside the repository**, at any depth, dangling ones included. A
     migrated repo is exactly where one turns up: a vendored path, a shared
     assets directory, a link to a config file elsewhere on the author's
     machine, a link left by an old build layout. It shows nothing useful in
     `ls` or a file tree, so scan the index with the check in
     `inno-safety-preflight` §2, which is the plugin's copy of it, and
     replace each hit with the real directory or file inside the repository,
     or drop it.

   List every existing file under `.github/workflows/`. The platform's caller
   workflow must live at exactly `.github/workflows/deploy.yml` (the platform
   re-dispatches that file name for security respins), so an existing
   `deploy.yml`, often a live pipeline to another host with its own secrets,
   has to be renamed (for example to `legacy-deploy.yml`) or retired, and that
   is the user's decision. Any workflow that passes `secrets: inherit` also
   fails the `sast` gate; the fix is to drop the line or pass only the named
   secrets that workflow needs.

   Also list every `.semgrepignore` file and `# nosemgrep` comment in the repo.
   The `sast` gate honors neither (R8), so whatever they hid becomes a
   finding: list those findings and plan to fix them.

   Inventory every value the app reads from its environment or a `.env`
   file: each becomes an app **Variable** (`set_app_variables`, all of them
   in one call) after registration, delivered back to the code as a real
   env var; nothing stays in the repo. Consider also declaring them in
   `app/inno-variables.json` so the platform's Variables tab and
   `app_status` can tell the owner what's still unset.
6. **What does not carry over**: custom domains, background jobs/cron, and any
   always-on/websocket assumptions.
7. **Proposed app name.** The name rules, every `check_name` answer and the
   active-app limit have one home: `inno-new-app` §1's name bullet. Follow it
   here unchanged, including checking the name before you propose it. One
   thing this flow adds: the name is independent of the repo name, though it
   does drive the app's hostname, so choose it for the hostname rather than
   carrying the repo name across. Quote the exact URL from `register_app`'s
   response; never construct it.
   Also ask who else needs access: optional email addresses they sign in
   with feed `register_app`'s
   `members` and can be added later via `inno-manage-app`.
8. **Accessibility** (an app with browser pages; an MCP server or an API-only
   app has none, so say it does not apply): who uses it, the main flows a
   person has to complete, and how each works today from the keyboard alone
   and with a screen reader. Walk the existing pages against
   `get_app_accessibility` and note what is missing: `lang`, real titles,
   labeled form controls, visible focus, controls built from `<div>`s, and
   any response headers `get_app_security` §9 lists that the app does not
   send.
9. **Identity, and who the app is for.** Ask the user the identity question
   in these words: **"does the app need to know who each caller is?"** Yes
   is `identity-aware`, the default, and the answer for most migrated apps,
   since they had a sign-in of their own. No is `anonymous`: the app is
   never told who the caller is, at any audience, takes no Connections,
   follows the contract's R10 (no accounts, no per-person views, and what a
   visitor submits is stored and never rendered), and is the only kind of
   app that can be made public. Identity is fixed at registration, like the
   type. Then ask who should reach the app in the end. It starts
   members-only; internal (everyone who signs in) or public (anyone on the
   internet) comes later, through `inno-manage-app`'s widening review.
   **A public site's new address is the main cost to name.** An app that is
   public today (anyone reaches it without signing in) can be public here
   only as an anonymous app, at the platform's address for its name, so its
   address changes: every link, bookmark and search result that points at
   the old address breaks unless the old host redirects to the new one.
   And an app with a signed-in part as well (an editing area, an admin
   view, submissions staff read) becomes two apps: read the `inno-new-app`
   skill's `references/two-app-pattern.md` and plan both.

Run a **guardrails** review too: call `get_guardrails` and judge the app's name,
purpose, and behavior against it. A conflict is a HARD STOP: you must not pass
`accept_guardrails: true` (which `register_app` requires) until it's clean or the
user has an explicit admin exception.

### Present the plan, THEN ask for approval

The user deserves to see what they're approving. **Write the full migration
plan into your visible reply as a structured section, never a one-line
summary buried inside a tool-approval prompt.** An approval question that
references "the plan as described" when no plan appears in the conversation
is a defect, not a shortcut: the user cannot approve what they have not seen.

The written plan covers, at minimum, each assessment product above:

- **Deployment type** and why (and the Connection constraint if it applied)
- **Identity and audience** (item 9): identity-aware or anonymous, the
  audience it is meant to be widened to later, and, for a public site, its
  new address and any split into two apps
- **Auth being stripped**: the specific files/routes removed, and what
  replaces them (the front door's identity headers; a Connection, if
  flagged in step 2)
- **Persistence changes**: what moves to D1/R2, and every blocker by name
- **Contract adaptations**: port/healthz/non-root/`app/` layout/CLAUDE.md
- **Gate risks found**: secrets (including git history), CVEs, semgrep hits,
  files that must be deleted before CI will pass
- **Existing workflows**: each file under `.github/workflows/`, what happens to
  an existing `deploy.yml` (renamed or retired), and any `secrets: inherit` line
  to remove
- **What does not carry over**
- **Proposed name** (checked available) and the exact hostname consequence
- **Accessibility**: item 8's users, flows and keyboard and screen-reader
  paths, and the fixes the migration will make
- **How the repo is protected**: the branch/restore-point strategy Phase 2
  will use, and the writes registration itself makes on the default branch,
  so the user approves them in advance: the one small commit of a
  proof-of-control file under `.inno-platform/`, and, when the repo has a
  top-level `scaffold/` directory, the commit call 2 pushes to rewrite it
  (Phase 2 step 1)
- **Effort summary and open decisions** (read-only default, members, …)

Only after that plan is in your reply: **stop and get explicit user approval**
(of the plan *and* the name) before Phase 2. Ask the approval question in
your own words referencing the plan the user can now read; put genuinely
separate decisions (name choice, identity, read-only default, members) in
their own questions rather than folding them into the approval. If a blocker
means the
app cannot function on the platform at all, say so plainly and stop here.

## Phase 2: Register and adapt in place (only after approval)

**Protect the current state first: you're editing the user's real repo.**
Before adapting anything, make sure the repo's current state is safe to fall
back to: confirm the working tree is committed and pushed (`git status`), and
capture a restore point, either a branch or tag on the pre-migration commit
(`git branch pre-inno-migration`), or do the adaptation on a feature branch
and merge to the default branch once it's ready. Tell the user where the
restore point is.

1. **Register the repo (two calls, with a proof file between them).** Call
   `register_app({ app, repo, description, type, identity, members, accept_guardrails: true, connections })`
   with the app name from Phase 1 in `app` (the wire parameter is `app`, not
   `name`) and the user's existing `owner/repo` slug in `repo` (a **slug, not a
   URL**). Those two are the only two the schema requires. Pass
   `identity: "anonymous"` when item 9 chose it, and omit it otherwise: the
   call that creates the app (call 2) fixes its identity, a call that
   resumes or repeats a registration keeps the identity the app has, and
   call 2's answer names it on its `Identity:` line, so pass the same
   `identity` both times (call 1 does not record it) and check that line:
   if it is not the one the plan chose, stop and tell the user before
   adapting anything, since a different identity is a new app. Call 2 may
   leave `type` and `description` out: the first call's are used, and one
   call 2 names differently is kept from the first, on a `WARNING:` or
   `NOTE:` line of its answer. Settle the type before call 1: the App often
   covers the repo already, and then a repeated call 1 cannot change it
   (`inno-new-app` §3's `type` bullet has the rule). Pass `connections`
   only if step 2's assessment found per-user backend auth to replace: a list of
   the names you plan to set up. It creates nothing (only `set_app_connection`
   can); for an identity-aware `mcp-container` the response echoes it back as
   a reminder to configure each one, and any other type's answer says the app
   takes no Connections (`set_app_connection` refuses it
   `app_type_unsupported`), the sign that the type is wrong for a per-user
   backend. A migrated app whose per-user backend auth must stay needs the
   `mcp-container` type, settled before call 1 (`inno-add-connection` step
   1). An anonymous app takes none (`app_anonymous`). The
   repo already exists, so ignore the response's "create it first from the
   platform template" note.

   The first call returns text beginning `Registration started …` with two
   things to act on, in this order:
   - a **proof-of-control file**: an exact `path:` under `.inno-platform/` and
     exact `contents:`. Commit that file, with exactly those contents, on the
     repo's **default branch** and push it. The default branch may not be
     `main`; `gh repo view <owner/repo> --json defaultBranchRef -q .defaultBranchRef.name`
     names it. The restore-point branch or a migration feature branch does not
     count: the platform reads only the default branch. If that branch is
     protected against direct pushes, land the file through a pull request
     merged into it. Do this with the user's own `git` or `gh`; it is not a
     user-only step. Leave the file in place: call 2 re-checks it.
   - an **App install link**: give it to the user and have them **install the
     platform GitHub App** on the account/org that owns the repo, scoped to that
     repository. If the App already covers the repo (including "All
     repositories"), they can skip the link. A setup page that says **GitHub
     App installed** (rather than **Repository verified**) is fine: run call 2.

   The rest of call 1 (the setup page's titles, the link's expiry, a new
   proof path after it) is `inno-new-app` §3's: follow it there.

   Once the proof file is on the default branch and the App is installed, call
   `register_app` **again with the same arguments** (`type` and
   `description` may be left out, `identity` may not); the second call binds the
   repo and returns the app URL and a `deploy.yml`. If the repo carries a
   top-level `scaffold/` directory, call 2 treats it as a template copy's,
   in a server-side commit on the repo's default branch, the commit the plan
   named: for a `container` app it deletes `scaffold/` wholesale, and for
   another type it lays `scaffold/<type>/` over the root when the repo has
   one, or else leaves the repo untouched and warns (`register_app`'s
   description says the rest). So `git pull` before editing. Branch on the
   response the same way `inno-new-app` §3 documents (`repo_control_unproven`,
   `name_quarantined`, `repo_already_registered`, `repo_owner_claimed`,
   `repo_identity_changed`, `app_limit_reached`, `repo_mismatch`,
   `guardrails_not_accepted`, `email_domain_not_allowed`, `host_in_use`,
   `app_anonymous`, …), including what happens to each address in
   `members`.
2. **Add the caller workflow.** Write `.github/workflows/deploy.yml` exactly as
   `register_app` returned it. If the repo already has a `deploy.yml`, never
   overwrite it silently: rename or retire it only as the approved plan says,
   and if the plan did not cover it, show the user the file and ask first. With
   the user's okay, remove `secrets: inherit` from any workflow that carries it
   (or pass only the named secrets it needs); the platform workflow needs no
   caller secrets. The returned file
   references the workflow on the `CI workflow:` line of the status you read in
   the Version gate (the instance's CI mirror; use the exact reference
   `register_app` returns) and passes `with: app: {name}`; keep its `workflow_dispatch` trigger (the
   platform re-dispatches it for security respins). The `with:` block matters
   most in a migration, because a migrated repo's name rarely matches the app's name. The broker resolves the real app
   from the signed repository id and refuses the run with `app_mismatch` when
   the asserted name disagrees. It is a thin caller: editing
   it can't bypass any gate (the broker's OIDC `job_workflow_ref` check enforces
   provenance), only break the deploy.
3. **Make the repo contract-compliant**, in place, per
   `inno-platform-conventions` (and `inno-containerize` for a container):
   - App code under **`app/`**; entrypoint listens on **8080** and serves
     **`/healthz`** (container) or is `app/index.ts` exporting a `fetch` handler
     (function).
   - **Auth deleted**; the caller read through the template's identity
     helper, copied from the template repo (the `Template repo:` line) when
     the repo lacks it: `current_user(request)` in `app/storage.py` (Python
     container), `currentUser` in `lib/storage.js` (JS or TS container), or
     `app/identity.ts` from `scaffold/function/app/` or
     `scaffold/mcp-function/app/` (function-shaped). Any other stack reads
     `X-Forwarded-User` and `X-Forwarded-Subject` by the same contract.
     Handle no user first in each route that needs a person, never in a
     middleware, and never default it into a value
     (`inno-platform-conventions`' **Identity** section says why); an MCP
     app refuses inside MCP, never with an HTTP status (a MUST of §1.2 and
     §1.3). Per-person data and any in-app roles are kept
     in the app's own store keyed on the caller's subject,
     `X-Forwarded-Subject` (Phase 1 step 2). Every cookie a browser app sets
     follows `inno-platform-conventions`' **Every cookie your app sets**
     paragraph (the `__Host-` prefix, so `Secure`, `Path=/` and no `Domain`,
     and `HttpOnly` unless the app's own script must read it), which binds an
     identity-aware app as it binds an anonymous one: the CSRF, flash and
     preference cookies a migrated app keeps after its sign-in is stripped
     included. It routes nothing under `/_auth/` (R3).
     If the app trusts proxy headers (a proxy-fix middleware, a trust-proxy
     setting, or a server's proxy-headers flag), trust only the three that
     R3's table says the front door sets itself (`X-Forwarded-For`,
     `X-Forwarded-Host` and `X-Forwarded-Proto`); every other proxy header
     (`X-Real-IP`, `True-Client-IP` and `X-Forwarded-Port` among them)
     stays caller-controlled and must never feed identity, origin or access
     decisions.
   - **An anonymous app** (item 9) reads no identity at all: it deletes the
     auth and every account, per-person view and per-person key or limit
     with it (R10), reads no `X-Forwarded-*` identity header (they arrive
     present and empty on every request), and shows no sign-out link. Its
     cookies follow the same paragraph.
   - **Persistence rewired** to the storage endpoints (container) or the app's
     `env.DATA`/`env.FILES` bindings (function).
   - **Dependencies** pinned in the stack's manifest under `app/`, CVE-clean.
     A function-shaped app (`function`, `mcp-function`) must declare every
     package it imports in `app/package.json` and commit a matching
     `app/package-lock.json` (run `npm install` inside `app/`). The migration
     trap is that CI installs `--omit=dev` and nothing is installed at the
     repo root, so an import the repo used to satisfy from a root
     `package.json` or from `devDependencies` now fails to bundle. The whole
     rule is `inno-platform-conventions`' **Node apps** paragraph.
   - **Dockerfile** (container) written per `inno-containerize` for the app's
     actual runtime.
   - A root **`CLAUDE.md`** carrying the required section headers: start
     from the guide `inno-new-app`'s `references/hand-authored-layout.md`
     names for the app's type and identity (an anonymous app keeps its
     guide's anonymous rules as they are), and when the repo already has a
     `CLAUDE.md`, merge into it as that file says, with the user's okay,
     rather than replacing it. Only the headers are gate-checked; rewrite the
     rest of the body to describe this app's real stack. The platform lays a
     guide at registration only from a template copy's scaffold: a type's
     overlay `CLAUDE.md` from `scaffold/<type>/`, and an anonymous app's from
     `scaffold/anonymous/<type>/`. A migrated repo carries neither, so the
     guide is yours to lay.
   - **Remove or move every forbidden path** flagged in Phase 1, working from
     the list in `inno-platform-conventions`' **Files you must not touch**
     section. Move code out of a repo-root `src/` (for example to `app/src/`,
     updating the Dockerfile's `COPY` paths) rather than deleting it, and get
     the user's okay before touching anything that could be theirs. The `.env`
     values move to app **Variables** (`set_app_variables`); the code keeps
     reading the same environment names, so this is usually a zero-code
     change.
   - Delete `app/.needs-build` if the repo carries one (CI skips deploys while
     it's present).
   - **Browser pages** (recommended, contract §3; not a gate by default): add
     what item 8 found missing, `<html lang>`, a real `<title>`, labeled form
     controls and visible focus styles, plus one middleware that sets the
     response headers `get_app_security` §9 lists. In an SPA, handle route
     changes too: update `document.title` and move focus to the new view.
     The served notes carry the detail; the plugin's summary is
     `inno-platform-conventions`' **Accessibility** section and **Response
     headers** paragraph.
4. **Secrets in history**: because this is the same repo, a credential in any
   past commit still trips the `secrets` gate. Rotate it first (a history
   rewrite alone doesn't un-leak it), then, before shipping, either remove it
   from the history or record its finding's fingerprint in `.gitleaksignore`,
   as Phase 1's **Gate risks** and `inno-ship`'s `secrets` row say; never
   delete the file in a new commit, which leaves the secret in the old one.
   Set the rotated value as an app **Variable**; never re-commit it.
5. **Rewrite `README.md`** to describe the migrated app (what it does, who it's
   for, its URL), drawing on the existing README. Platform mechanics stay in
   `CLAUDE.md`, not here.
6. **Backend auth Phase 1 flagged**: if the assessment (step 2 above) found
   the app running its own auth against an outside backend, set that up as a
   Connection now via the `inno-add-connection` skill instead of porting the
   old code.

## Hand off

End the same way `inno-new-app` does: the next steps are `inno-safety-preflight`
(it pushes to the default branch, which runs the real gates and deploys
nothing), then `inno-ship`. Beyond the registration proof file, don't commit or
push unless asked. If gates fail
after pushing, map the failing job through `inno-ship`'s table. If the user
abandons the migration after registering, point at `inno-manage-app` (`stop_app`)
so the app winds down; uninstalling the GitHub App also unlinks and stops it.

Tell the user the deadline too, exactly as `inno-new-app` §5 does: its
date and time from call 2's answer, its reminder, and where a pinned app's
is read. A migration that will take longer than that needs its first
release before the date, or a fresh registration after it.
When the registration named members, say they are told when the app first
deploys, not now. Point the user at the platform's user guide too: the
`Panel URL:` address with `/guide` after it, readable by anyone signed in to
the platform.
