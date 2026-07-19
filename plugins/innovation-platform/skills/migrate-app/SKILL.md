---
name: migrate-app
description: Use when the user has an EXISTING repo or codebase they want on the Innovation Platform ("deploy this to the innovation platform", "migrate this app", "convert this repo"). Assesses fit read-only, gets approval, provisions via create_app, then ports the code into the new inno-{app} repo — keeping its original stack where the platform's gates allow.
---

# migrate-app

An existing repo can never be deployed to the platform in place: the deploy
broker only mints tokens for registered `inno-{app}` repos whose CI run
executed the platform's reusable workflow, and the `config-integrity` gate
requires the template files intact. Migration therefore means porting the
code **into a freshly provisioned repo**. This skill does that in two phases
with an approval gate between them. The source repo is **never modified**.

Requires the `inno-platform` MCP server (ships with this plugin). The first
tool call triggers an Okta browser login — expected, not an error.

## Phase 1 — Assess (read-only; provision nothing yet)

Scan the existing repo and present a **migration assessment** covering, in
order:

1. **Stack** — language, framework, entrypoint, current listen port. The
   container contract is language-agnostic (see `containerize`), so the
   original stack is usually keepable as-is; the platform's Python/Starlette
   conventions apply to *template-scaffolded* apps, not migrated ones. One
   known trap: **FastAPI** is keepable only if its resolved Starlette version
   clears `pip-audit`/Trivy (older pins drag in CVE-bearing `starlette
   0.46.x` — check the lockfile/requirements, don't assume).
2. **Auth to strip** — login routes, session middleware, password storage,
   OAuth flows. All of it goes: the gateway verifies the user against Okta
   and injects `X-Forwarded-User` / `X-Forwarded-Groups` (see
   `platform-conventions`). List each file/route that must be removed.
3. **Persistence to port** — local files and SQLite move to the platform's
   storage endpoints (D1 for SQL, R2 for files) reached at
   `http://storage.internal` (`/_storage/*`). Python apps use the template's
   `app/storage.py` client; JS apps the JS client; any other stack calls the
   HTTP endpoints directly. Dependencies the platform cannot provide —
   Postgres-specific SQL, Redis, queues, third-party managed services — are
   **blockers**: name them explicitly, never silently drop them.
4. **Container contract deltas** — what changes to reach: listens on 8080,
   serves `/healthz`, runs non-root, patched base image (see `containerize`).
5. **Gate risks** — secrets in the working tree (gitleaks), dependency CVEs
   (`pip-audit` for Python requirements; the Trivy image scan covers
   everything the container installs — CI's `npm audit` only checks the
   template's own root `package.json`), semgrep OWASP patterns such as
   string-built HTML or raw SQL formatting.
6. **What does not carry over** — git history (fresh repo; secrets buried in
   old history become moot, but working-tree secrets do not), custom
   domains, background jobs/cron, and any always-on/websocket assumptions.
7. **Proposed app name** — must match `^[a-z][a-z0-9-]{2,28}$`; a few names
   are reserved server-side, so have a fallback. The repo becomes
   `inno-{name}` and the URL `https://inno-{name}.davidlaporte.org`. Also
   ask who else needs access — optional initial members' Okta emails feed
   `create_app`'s `members` and can be added later via `manage-app`.

Close the assessment with an effort summary and the blocker list, then
**stop and get explicit user approval** (of the plan *and* the name) before
Phase 2. Provisioning is real — GitHub repo, Okta group, D1 database, R2
bucket — and the assessment may surface showstoppers that change the user's
mind. If a blocker means the app cannot function on the platform at all, say
so plainly and stop here.

## Phase 2 — Provision and port (only after approval)

1. Call `create_app({ name, description, members })` — same semantics as
   `new-app`: owner is the signed-in Okta user, provisioning is synchronous
   (~15-30s), and a non-empty `error` field is surfaced verbatim, not
   retried blindly. One behavior matters here: `create_app` is
   restore-aware — if the chosen name belongs to one of the caller's own
   decommissioned apps still inside its retention window, the response
   starts with `Restored "{name}"` instead of `App "{name}" created.`,
   the cloned repo contains the OLD app's code (not the template), and
   its retained D1/R2 data re-attaches. If that happens, STOP and
   confirm with the user (or rerun with a different name) before porting
   anything.
2. `git clone https://github.com/dlaporte/inno-{name}.git` and work in the
   clone.
3. Port the code **into `app/`**, replacing the template's example app.
   Never touch the gate-pinned template files: `src/gateway/`,
   `package.json`, `package-lock.json`, `tsconfig.json`, the `CLAUDE.md`
   required headers, or `wrangler.jsonc`'s orchestrator-managed fields —
   and never add a competing `wrangler.json`/`wrangler.toml`/`.wrangler/`.
   (`config-integrity` rejects all of these; see `platform-conventions`.)
   Leave `.github/workflows/deploy.yml` as templated too — it is NOT
   gate-pinned (the broker's OIDC `job_workflow_ref` check carries that
   enforcement, so editing the caller workflow can't bypass anything;
   it can only break the deploy).
4. Adapt while porting:
   - entrypoint listens on **8080** and serves **`/healthz`**;
   - auth code deleted, identity read from `X-Forwarded-User` (Python: the
     template's `current_user(request)` helper);
   - persistence rewired to the storage endpoints (keep the template's
     `app/storage.py` for Python even when the rest of the example app is
     replaced);
   - dependencies pinned in the stack's manifest (`app/requirements.txt`
     for Python), CVE-clean;
   - Dockerfile rewritten per `containerize` for the app's actual runtime.
5. Write **`MIGRATION.md`** at the repo root (extra root files pass the
   gates): what was ported, what was stripped (auth, dropped services),
   what was rewired (storage), deferred TODOs, and any open blockers with
   suggested next steps. A blocker discovered only mid-port goes into
   `MIGRATION.md` if the app still functions without the blocked piece;
   if it can't, stop and ask the user before continuing.
6. Leave the source repo untouched; tell the user where it stayed.

## Hand off

End the same way `new-app` does: the next steps are `preflight` locally,
then `ship` — don't commit or push unless asked. If gates fail after
pushing, map the failing job through `ship`'s table. If the user abandons
the migration after provisioning, point at `manage-app`
(`decommission_app`) so the provisioned resources don't linger.
