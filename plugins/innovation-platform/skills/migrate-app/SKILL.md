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

1. **Stack — keeping vs. porting is the user's decision, informed by your
   analysis.** The platform contract is **HTTP on port 8080**, not a language:
   the gateway proxies authenticated requests to your container over HTTP, and
   **no CI gate checks the language or framework** (`config-integrity` pins the
   *gateway* and template files, never your `app/` code's stack). Keeping the
   existing stack — TypeScript/Express, Go, Ruby, whatever — is usually the
   right call and the default bias; Python/Starlette is only the *template
   default* for brand-new apps (`new-app`), never a migration requirement. But
   whether to keep or port is a genuine choice, and it is **the user's to
   make** — your job is to inform it, not to decide unilaterally in either
   direction. Assess and present:
   - **Can the current stack meet the platform requirements?** The container
     contract (8080, `/healthz`, non-root, patched base image) and the security
     gates (Trivy / `pip-audit` / `npm audit`, semgrep, no committed secrets).
     Most stacks can, as-is.
   - **How complex would a port be?** Rough effort and risk of porting vs.
     adapting the app in place.
   - **Any deal-breakers?** A hard blocker that makes keeping the stack
     impossible (e.g. it fundamentally cannot satisfy the container contract)
     *forces* a port — call that out plainly. Absent a deal-breaker, give a
     recommendation but **leave the decision to the user**: don't port
     unilaterally, and don't refuse to port if that's what they want.
   Note the entrypoint, framework, and listen port either way, so you can adapt
   them to 8080 + `/healthz`. One known trap: **FastAPI** is keepable only if
   its resolved Starlette version clears `pip-audit`/Trivy (older pins drag in
   CVE-bearing `starlette 0.46.x` — check the lockfile, don't assume).
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
   `inno-{name}` and the URL `https://inno-{name}.davidlaporte.org`.
   **Check the name with the `check_name` MCP tool (read-only) before you
   propose it — don't recommend a name you haven't confirmed is available.**
   Only put forward a name `check_name` reports as **available**; if it's
   in-use/reserved/invalid, pick another, and if it's the caller's own
   existing app, surface that (a stopped app is brought back with `start_app`,
   not by re-creating it). `list_apps` only sees the caller's own apps, so it
   can't confirm platform-wide freeness.
   Also ask who else needs access — optional initial members' Okta emails feed
   `create_app`'s `members` and can be added later via `manage-app`.

Close the assessment with an effort summary and the blocker list, then
**stop and get explicit user approval** (of the plan *and* the name) before
Phase 2. Provisioning is real — GitHub repo, Okta group, D1 database, R2
bucket — and the assessment may surface showstoppers that change the user's
mind. If a blocker means the app cannot function on the platform at all, say
so plainly and stop here.

## Phase 2 — Provision and port (only after approval)

**First, protect the original — a migration must be reversible.** Porting
happens entirely in the new `inno-{app}` repo and never modifies the source
(step 6), but before you start, make sure a **validated backup** of the original
code exists to fall back on, with steps appropriate to its current state:

- **Clean git repo with a remote** — already safe: confirm the working tree is
  clean and pushed (`git status`, `git log @{u}..`) and note the commit as the
  restore point.
- **Git repo with uncommitted changes** — capture the exact starting state:
  offer to commit it to a branch or tag (or stash) so nothing in flight is lost.
- **No version control (a loose directory)** — offer to snapshot it first: `git
  init` + an initial commit, a dated copy of the directory, or clone/push it to
  a new private repo. Don't begin porting until one of these exists.

**Validate** the backup (files present, push succeeded) and tell the user where
it is, so if the port isn't what they wanted the original is intact and they can
retry or walk away.

1. Call `create_app({ name, description, members })` — same semantics as
   `new-app`: owner is the signed-in Okta user, provisioning is synchronous
   (~15-30s), and a non-empty `error` field is surfaced verbatim, not
   retried blindly. One behavior matters here: if the chosen name belongs to
   one of the caller's own existing apps (including a stopped one), the
   response says so instead of creating — STOP and confirm with the user
   (or rerun with a different name) before porting anything. A previously
   purged app leaves only its repo behind: `create_app` on that name creates
   fresh, but the generated repo may collide with the old one on GitHub —
   surface the create response verbatim if it errors.
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
   Also delete the template's scaffold marker so the migrated app can deploy —
   it is a hidden file that "replacing the example app" won't remove on its own:

   ```bash
   rm -f app/.needs-build
   ```

   (While `app/.needs-build` is present, CI skips deployment and `ship` refuses
   to push.)
4. Adapt while porting:
   - entrypoint listens on **8080** and serves **`/healthz`**;
   - auth code deleted, identity read from `X-Forwarded-User` (Python: the
     template's `current_user(request)` helper);
   - persistence rewired to the storage endpoints (keep the template's
     `app/storage.py` for Python even when the rest of the example app is
     replaced);
   - dependencies pinned in the stack's manifest (`app/requirements.txt`
     for Python), CVE-clean;
   - Dockerfile rewritten per `containerize` for the app's actual runtime;
   - **CLAUDE.md** — keep the five required section headers (`config-integrity`
     checks their presence), but rewrite the *body* to describe the migrated
     app's actual stack. The template's CLAUDE.md says "the stack is Starlette";
     left unedited it ships in the repo and misleads every future Claude session
     (and Claude Code auto-loads it) into thinking a TS/Go/Ruby app must be
     Python. Editing the body is safe — only the headers are gate-checked.
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
(`stop_app`) so the app winds down — it purges automatically when the start window closes.
