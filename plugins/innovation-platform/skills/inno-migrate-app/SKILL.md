---
name: inno-migrate-app
description: Use when the user has an EXISTING repo or codebase they want on the Innovation Platform ("deploy this to the innovation platform", "migrate this app", "put this repo on inno-platform"). Registers the user's existing repo in place via register_app and adapts it to the platform contract — no copying into a new repo, keeping its stack where the gates allow.
---

# inno-migrate-app

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

An existing repo now deploys **in place**. You register the user's **own** repo
with the `register_app` MCP tool and make that same repo satisfy the platform
contract — there is no porting into a freshly provisioned `inno-{app}` repo and
no copying. The repo stays the user's, on their account/org, public or private.

This differs from `inno-new-app` only in the starting point: new-app has the
user create a fresh repo from `inno-template`; here the user already has a repo.
If their repo is **already built to the platform contract** (app code under
`app/`, a `CLAUDE.md` with the required headers, `/healthz`, identity from the
gateway headers), migration is just: `register_app`, commit the proof file it
names, install the platform GitHub App on the repo, and `register_app` again. If it's an **arbitrary app** not written for the platform, you
assess it, then adapt it in place before shipping.

Requires the `inno-platform` MCP server (ships with this plugin). The first tool
call triggers an Okta browser login — expected, not an error.

## Phase 1 — Assess (read-only; register nothing yet)

**Fetch the `get_app_contract` MCP tool first — it IS the assessment
checklist**: the full requirement list, the deployment patterns, what the
platform does NOT support (background jobs, machine-to-machine APIs, guaranteed
long-lived connections — instant blockers to surface), and the current
recommended base images. Judge the repo against the contract, not a remembered
summary of it.

Scan the existing repo and present a **migration assessment** covering, in
order:

1. **Stack — keep vs. adapt is the user's decision, informed by your analysis.**
   Present findings to the user in plain language — name specific technologies
   (Cloudflare, D1, R2, Okta, wrangler) only if the user has shown technical
   fluency; the precision below is for your assessment, not recitation.

   The platform contract is **HTTP on port 8080** (container) or a Cloudflare
   Worker `fetch` handler (function), **not a language**: no CI gate checks the language or
   framework. Keeping the existing stack — TypeScript/Express, Go, Ruby,
   Python, whatever — is usually the right call and the default bias. Present:
   - **Can the current stack meet the platform requirements?** The container
     contract (8080, `/healthz`, non-root, patched base image) and the security
     gates (Trivy / `pip-audit` / `npm audit`, semgrep, no committed secrets).
     Most stacks can, as-is.
   - **Deployment type** — default **`container`** (keeps any stack). Only raise
     **`function`** when the source is already JS/TS and reimplementing it as a
     Cloudflare Worker is a deliberate choice the user opts into (closer to a
     rewrite; see `get_app_contract` §1.1). If the source is an **MCP server**,
     raise **`mcp-function`** for a TS/JS source (MCP TypeScript SDK's Streamable
     HTTP transport, stateless — `get_app_contract` §1.2) or **`mcp-container`**
     for a Python/other-stack source (container contract plus `POST /mcp`,
     stateless — §1.3). **Exception:** if the MCP source needs a per-user
     **Connection** to a backend (step 2 below), it MUST be `mcp-container`
     even when the source is TS/JS — `mcp-function` cannot consume a Connection
     in v1. CRITICAL for a Python source using FastMCP (the `mcp`
     SDK): construct it with
     `transport_security=TransportSecuritySettings(enable_dns_rebinding_protection=False)`
     (import from `mcp.server.transport_security`) — FastMCP otherwise
     auto-enables localhost-only Host validation and every gateway-forwarded
     `/mcp` request dies with `421 Invalid Host header` (§1.3 records this).
   - **Any deal-breakers?** A hard blocker that makes the platform unable to run
     the app at all — call it out plainly. One known trap: **FastAPI** is
     keepable only if its resolved Starlette version clears `pip-audit`/Trivy
     (older pins drag in CVE-bearing `starlette 0.46.x` — check the lockfile).
   Note the entrypoint, framework, and listen port so you can adapt them to
   8080 + `/healthz`.
2. **Auth to strip**: login routes, session middleware, password storage, OAuth
   flows. All of it goes: the gateway verifies the user against Okta and injects
   `X-Forwarded-User` / `X-Forwarded-Groups` (see `inno-platform-conventions`).
   List each file/route to remove. Keep the app's own **authorization** (who may
   edit what), rewired to key on `X-Forwarded-User`: `X-Forwarded-Groups`
   carries only this app's `inno-{name}-users` and `inno-{name}-open`, never the
   platform admin group, another app's groups, or the repo's existing role
   groups (for an SSO app from its first deploy on the v0.14.3 gateway onward;
   MCP apps get the narrowed header immediately), so existing role checks cannot
   move onto that header. This is about the app's *own* front-door
   login — a separate thing to look for is auth to a *backend the app calls
   out to*: if the repo runs its own OAuth flow against some other service,
   holds a long-lived per-user token for that service, or ships a sidecar
   whose whole job is minting/refreshing that credential, don't port any of
   it — that's exactly what a Connection replaces. Flag it in the assessment
   and point at the `inno-add-connection` skill for Phase 2 instead of
   carrying the old backend-auth code forward (note: needs the `mcp-container`
   type, §1's deployment-type bullet).
3. **Persistence to port** — local files and SQLite move to the platform's
   storage (D1 for SQL, R2 for files) reached at `http://storage.internal`
   (container) or the app's own `env.DATA`/`env.FILES` bindings (function).
   Dependencies the platform cannot provide — Postgres-specific SQL, Redis,
   queues, third-party managed services — are **blockers**: name them, never
   silently drop them.
4. **Contract deltas** — listens on 8080, serves `/healthz`, runs non-root,
   patched base image (container; see `inno-containerize`); app code arranged
   under `app/`; a root `CLAUDE.md` carrying the platform's required section
   headers (config-integrity checks these — copy `dlaporte/inno-template`'s
   `CLAUDE.md` and adapt its body). The repo's **default branch** needs no
   special handling: registration's scaffold prune and the `deploy.yml` that
   `register_app` returns both target the repo's actual default branch,
   whatever it is named (platform v0.14.5), and `inno-safety-preflight` and
   `inno-ship` push to that same branch.
5. **Gate risks**: secrets **anywhere in git history** (gitleaks scans the full
   history, and this is the *same* repo: history is not left behind, so a
   secret buried in an old commit still fails and must be scrubbed AND rotated;
   the rotated value then goes into an app Variable, never back in the repo),
   dependency CVEs (`pip-audit`, Trivy), and semgrep OWASP patterns such as
   string-built HTML or raw SQL formatting. **Semgrep scans the whole repository
   except the repo-root `src/` and semgrep's default-ignored directories**
   (`test/`, `tests/`, `build/`, `dist/`, `vendor/`, `node_modules/`, at any
   depth), not just `app/`: root-level scripts, tools, workflow files and the
   Dockerfile all count, so a migrated repo's non-app files can fail the gate
   too. Then list every path the `config-integrity` gate rejects:
   - **anything under a repo-root `src/`** (the platform owns `src/`: its
     gateway was bundled from there, and the deploy wipes it). A repo whose
     code lives in `src/` must move it, for example to `app/src/`;
   - the repo-root `package.json`, `package-lock.json` and `tsconfig.json`
     (your own under `app/` are fine);
   - a `wrangler.*` config or a `.wrangler/` directory at the repo root;
   - a `.npmrc` at **any** depth, `app/.npmrc` included (npm expands
     environment variables into it);
   - at the repo root only: `.env` / `.env.*`, `.yarnrc`, `.yarnrc.yml`,
     `.pnpmfile.cjs`, `pnpm-workspace.yaml`, `bunfig.toml` (the same files
     under `app/` are allowed, except `.npmrc`);
   - a `scaffold/` directory, which is rejected unless `app/.needs-build` is
     still present.

   List every existing file under `.github/workflows/`. The platform's caller
   workflow must live at exactly `.github/workflows/deploy.yml` (the platform
   re-dispatches that file name for security respins), so an existing
   `deploy.yml`, often a live pipeline to another host with its own secrets,
   has to be renamed (for example to `legacy-deploy.yml`) or retired, and that
   is the user's decision. Any workflow that passes `secrets: inherit` also
   fails the `sast` gate; the fix is to drop the line or pass only the named
   secrets that workflow needs.

   Also list every `.semgrepignore` file and `# nosemgrep` comment in the repo.
   From platform v0.14.4 (contract version 13) the `sast` gate deletes every
   `.semgrepignore` before it scans and ignores `# nosemgrep`, so whatever they
   hid becomes a finding: list those findings and plan to fix them.

   Inventory every value the app reads from its environment or a `.env` file:
   each becomes an app **Variable** (`set_app_variable`) after registration,
   delivered back to the code as a real env var; nothing stays in the repo.
6. **What does not carry over** — custom domains, background jobs/cron, and any
   always-on/websocket assumptions.
7. **Proposed app name** — lowercase letters/digits/hyphens, 3-29 chars,
   starting with a letter; a few names are reserved server-side, so have a
   fallback. A name ending in **`-app`** is rejected as well: the server
   returns `invalid_name` for `todo-app`, so propose `todo` instead. A repo
   called `something-app` makes that suffix an easy reflex, so drop it rather
   than carrying the repo name across. The name drives the app's hostname
   `inno-{name}.<platform domain>`
   (quote the exact URL from `register_app`'s response — never construct it);
   it is independent of the repo name.
   **Check the name with the `check_name` MCP tool (read-only) before you
   propose it.** Only put forward a name it reports as **available**; if it's
   in-use/reserved/invalid, pick another; if it reports the name **was recently
   purged and is held until** a UTC time, it belonged to an app purged in the
   last seven days and nobody, admins included, can register it before then:
   pick another or wait (`register_app` refuses it as `name_quarantined`); if
   it's the caller's own existing app,
   surface that (a stopped app is brought back with `start_app`, not by
   re-registering). **If `check_name` warns the user is at their active-app
   limit**, resolve that first: show their apps (`list_apps`) and offer — with
   explicit confirmation only — to `stop_app` one to make room; otherwise an
   admin raises their `apps.max_active`, or pause the migration.
   Also ask who else needs access — optional Okta emails feed `register_app`'s
   `members` and can be added later via `inno-manage-app`.

Run a **guardrails** review too: call `get_guardrails` and judge the app's name,
purpose, and behavior against it. A conflict is a HARD STOP — you must not pass
`accept_guardrails: true` (which `register_app` requires) until it's clean or the
user has an explicit admin exception.

### Present the plan, THEN ask for approval

The user deserves to see what they're approving. **Write the full migration
plan into your visible reply as a structured section — never a one-line
summary buried inside a tool-approval prompt.** An approval question that
references "the plan as described" when no plan appears in the conversation
is a defect, not a shortcut: the user cannot approve what they have not seen.

The written plan covers, at minimum, each assessment product above:

- **Deployment type** and why (and the Connection constraint if it applied)
- **Auth being stripped** — the specific files/routes removed, and what
  replaces them (gateway headers; a Connection, if flagged in step 2)
- **Persistence changes** — what moves to D1/R2, and every blocker by name
- **Contract adaptations** — port/healthz/non-root/`app/` layout/CLAUDE.md
- **Gate risks found** — secrets (including git history), CVEs, semgrep hits,
  files that must be deleted before CI will pass
- **Existing workflows**: each file under `.github/workflows/`, what happens to
  an existing `deploy.yml` (renamed or retired), and any `secrets: inherit` line
  to remove
- **What does not carry over**
- **Proposed name** (checked available) and the exact hostname consequence
- **How the repo is protected**: the branch/restore-point strategy Phase 2
  will use, and the one small commit registration itself needs on the default
  branch (a proof-of-control file under `.inno-platform/`), so the user approves
  that write in advance
- **Effort summary and open decisions** (read-only default, members, …)

Only after that plan is in your reply: **stop and get explicit user approval**
(of the plan *and* the name) before Phase 2. Ask the approval question in
your own words referencing the plan the user can now read; put genuinely
separate decisions (name choice, read-only default, members) in their own
questions rather than folding them into the approval. If a blocker means the
app cannot function on the platform at all, say so plainly and stop here.

## Phase 2 — Register and adapt in place (only after approval)

**Protect the current state first — you're editing the user's real repo.**
Before adapting anything, make sure the repo's current state is safe to fall
back to: confirm the working tree is committed and pushed (`git status`), and
capture a restore point — a branch or tag on the pre-migration commit
(`git branch pre-inno-migration`), or do the adaptation on a feature branch and
merge to `main` once it's ready. Tell the user where the restore point is.

1. **Register the repo (two calls, with a proof file between them).** Call
   `register_app({ app, repo, description, type, members, accept_guardrails: true, connections })`
   with the app name from Phase 1 in `app` (the wire parameter is `app`, not
   `name`) and the user's existing `owner/repo` slug in `repo` (a **slug, not a
   URL**). Those two are the only two the schema requires. Pass `connections`
   only if step 2's assessment found per-user backend auth to replace: a list of
   the names you plan to set up. It creates nothing (only `set_app_connection`
   can); the response echoes it back as a reminder to configure each one. The
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

   Once the proof file is on the default branch and the App is installed, call
   `register_app` **again with the same arguments**; the second call binds the
   repo and returns the app URL and a `deploy.yml`. If the repo carries a
   top-level `scaffold/` directory, call 2 may delete it in a server-side commit
   on the repo's default branch, so `git pull` before editing. Branch on the
   response the same way `inno-new-app` §3 documents (`repo_control_unproven`,
   `name_quarantined`, `repo_already_registered`, `repo_owner_claimed`,
   `app_limit_reached`, `repo_mismatch`, `guardrails_not_accepted`, …).
2. **Add the caller workflow.** Write `.github/workflows/deploy.yml` exactly as
   `register_app` returned it. If the repo already has a `deploy.yml`, never
   overwrite it silently: rename or retire it only as the approved plan says,
   and if the plan did not cover it, show the user the file and ask first. With
   the user's okay, remove `secrets: inherit` from any workflow that carries it
   (or pass only the named secrets it needs); the platform workflow needs no
   caller secrets. The returned file
   references `dlaporte/inno-platform-ci/.github/workflows/platform-ci.yml@main`
   and passes `with: app: {name}`; keep its `workflow_dispatch` trigger (the
   platform re-dispatches it for security respins). The `with:` block matters
   most in a migration: without it the reusable workflow derives the app name
   from the repository name with any `inno-` prefix removed, and a migrated repo
   rarely happens to be named `{name}` or `inno-{name}`. The broker resolves the real app
   from the signed repository id and refuses the run with `app_mismatch` when
   the asserted name disagrees. It is a thin caller — editing
   it can't bypass any gate (the broker's OIDC `job_workflow_ref` check enforces
   provenance), only break the deploy.
3. **Make the repo contract-compliant** — in place, per
   `inno-platform-conventions` (and `inno-containerize` for a container):
   - App code under **`app/`**; entrypoint listens on **8080** and serves
     **`/healthz`** (container) or is `app/index.ts` exporting a `fetch` handler
     (function).
   - **Auth deleted**; identity read from `X-Forwarded-User` (Python container:
     the reference `current_user(request)` helper), and any in-app roles kept
     in the app's own store keyed on that email (Phase 1 step 2). If the app
     trusts proxy headers (a proxy-fix middleware, a trust-proxy setting, or a
     server's proxy-headers flag), trust only `X-Forwarded-For`,
     `X-Forwarded-Host` and `X-Forwarded-Proto`, which the gateway sets itself;
     `X-Real-IP`, `True-Client-IP` and `X-Forwarded-Port` stay caller-controlled
     and must never feed identity, origin or access decisions.
   - **Persistence rewired** to the storage endpoints (container) or the app's
     `env.DATA`/`env.FILES` bindings (function).
   - **Dependencies** pinned in the stack's manifest under `app/`, CVE-clean.
     A function-shaped app (`function`, `mcp-function`) must declare every
     package it imports in `app/package.json` and commit a matching
     `app/package-lock.json` (run `npm install` inside `app/`): the deploy
     installs only from that lockfile with `npm ci`, refuses when it is missing,
     and installs nothing at the repo root, so an import the repo used to
     satisfy from a root `package.json` fails to bundle.
   - **Dockerfile** (container) written per `inno-containerize` for the app's
     actual runtime.
   - A root **`CLAUDE.md`** carrying the required section headers (copy
     `dlaporte/inno-template`'s and rewrite the body to describe this app's real
     stack — only the headers are gate-checked).
   - **Remove or move every forbidden path** flagged in Phase 1: move code out
     of a repo-root `src/` (for example to `app/src/`, updating the
     Dockerfile's `COPY` paths) and delete whatever remains there; delete the
     root `package.json`/`package-lock.json`/`tsconfig.json`, any root
     `wrangler.*` config, `.wrangler/`, `scaffold/`, every `.npmrc` at any
     depth, and the root `.env*`, `.yarnrc`, `.yarnrc.yml`, `.pnpmfile.cjs`,
     `pnpm-workspace.yaml` and `bunfig.toml`. The `.env` values move to app
     **Variables** (`set_app_variable`); the code keeps reading the same
     environment names, so this is usually a zero-code change.
   - Delete `app/.needs-build` if the repo carries one (CI skips deploys while
     it's present).
4. **Secrets in history** — because this is the same repo, a credential in any
   past commit still trips the `secrets` gate. Rotate it (a history rewrite
   alone doesn't un-leak it), scrub it from history before shipping, and set
   the rotated value as an app **Variable** — never re-commit it.
5. **Rewrite `README.md`** to describe the migrated app (what it does, who it's
   for, its URL), drawing on the existing README. Platform mechanics stay in
   `CLAUDE.md`, not here.
6. **Backend auth Phase 1 flagged** — if the assessment (step 2 above) found
   the app running its own auth against an outside backend, set that up as a
   Connection now via the `inno-add-connection` skill instead of porting the
   old code.

## Hand off

End the same way `inno-new-app` does: the next steps are `inno-safety-preflight`
locally, then `inno-ship`. Beyond the registration proof file, don't commit or
push unless asked. If gates fail
after pushing, map the failing job through `inno-ship`'s table. If the user
abandons the migration after registering, point at `inno-manage-app` (`stop_app`)
so the app winds down; uninstalling the GitHub App also unlinks and stops it.
