---
name: inno-migrate-app
description: Use when the user has an EXISTING repo or codebase they want on the Innovation Platform ("deploy this to the innovation platform", "migrate this app", "put this repo on inno-platform"). Registers the user's existing repo in place via register_app and adapts it to the platform contract — no copying into a new repo, keeping its stack where the gates allow.
---

# inno-migrate-app

An existing repo now deploys **in place**. You register the user's **own** repo
with the `register_app` MCP tool and make that same repo satisfy the platform
contract — there is no porting into a freshly provisioned `inno-{app}` repo and
no copying. The repo stays the user's, on their account/org, public or private.

This differs from `inno-new-app` only in the starting point: new-app has the
user create a fresh repo from `inno-template`; here the user already has a repo.
If their repo is **already built to the platform contract** (app code under
`app/`, a `CLAUDE.md` with the required headers, `/healthz`, identity from the
gateway headers), migration is just: install the platform GitHub App on it and
`register_app`. If it's an **arbitrary app** not written for the platform, you
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
   The platform contract is **HTTP on port 8080** (container) or a Worker
   `fetch` handler, **not a language**: no CI gate checks the language or
   framework. Keeping the existing stack — TypeScript/Express, Go, Ruby,
   Python, whatever — is usually the right call and the default bias. Present:
   - **Can the current stack meet the platform requirements?** The container
     contract (8080, `/healthz`, non-root, patched base image) and the security
     gates (Trivy / `pip-audit` / `npm audit`, semgrep, no committed secrets).
     Most stacks can, as-is.
   - **Deployment type** — default **`container`** (keeps any stack). Only raise
     **`worker`** when the source is already JS/TS and reimplementing it as a
     Cloudflare Worker is a deliberate choice the user opts into (closer to a
     rewrite; see `get_app_contract` §1.1).
   - **Any deal-breakers?** A hard blocker that makes the platform unable to run
     the app at all — call it out plainly. One known trap: **FastAPI** is
     keepable only if its resolved Starlette version clears `pip-audit`/Trivy
     (older pins drag in CVE-bearing `starlette 0.46.x` — check the lockfile).
   Note the entrypoint, framework, and listen port so you can adapt them to
   8080 + `/healthz`.
2. **Auth to strip** — login routes, session middleware, password storage, OAuth
   flows. All of it goes: the gateway verifies the user against Okta and injects
   `X-Forwarded-User` / `X-Forwarded-Groups` (see `inno-platform-conventions`).
   List each file/route to remove.
3. **Persistence to port** — local files and SQLite move to the platform's
   storage (D1 for SQL, R2 for files) reached at `http://storage.internal`
   (container) or the app's own `env.DATA`/`env.FILES` bindings (worker).
   Dependencies the platform cannot provide — Postgres-specific SQL, Redis,
   queues, third-party managed services — are **blockers**: name them, never
   silently drop them.
4. **Contract deltas** — listens on 8080, serves `/healthz`, runs non-root,
   patched base image (container; see `inno-containerize`); app code arranged
   under `app/`; a root `CLAUDE.md` carrying the platform's required section
   headers (config-integrity checks these — copy `dlaporte/inno-template`'s
   `CLAUDE.md` and adapt its body).
5. **Gate risks** — secrets **anywhere in git history** (gitleaks scans the full
   history, and this is the *same* repo — history is not left behind, so a
   secret buried in an old commit still fails and must be scrubbed AND rotated),
   dependency CVEs (`pip-audit`, Trivy), semgrep OWASP patterns such as
   string-built HTML or raw SQL formatting, and any platform-injected file that
   must NOT be committed (a root `package.json`/`package-lock.json`/`tsconfig.json`,
   `src/gateway/`, any `wrangler.*` config, `.env*`/`.npmrc`).
6. **What does not carry over** — custom domains, background jobs/cron, and any
   always-on/websocket assumptions.
7. **Proposed app name** — lowercase letters/digits/hyphens, 3-29 chars,
   starting with a letter; a few names are reserved server-side, so have a
   fallback. The name drives the app's hostname `inno-{name}.<platform domain>`
   (quote the exact URL from `register_app`'s response — never construct it);
   it is independent of the repo name.
   **Check the name with the `check_name` MCP tool (read-only) before you
   propose it.** Only put forward a name it reports as **available**; if it's
   in-use/reserved/invalid, pick another; if it's the caller's own existing app,
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

Close with an effort summary and the blocker list, then **stop and get explicit
user approval** (of the plan *and* the name) before Phase 2. If a blocker means
the app cannot function on the platform at all, say so plainly and stop here.

## Phase 2 — Register and adapt in place (only after approval)

**Protect the current state first — you're editing the user's real repo.**
Before adapting anything, make sure the repo's current state is safe to fall
back to: confirm the working tree is committed and pushed (`git status`), and
capture a restore point — a branch or tag on the pre-migration commit
(`git branch pre-inno-migration`), or do the adaptation on a feature branch and
merge to `main` once it's ready. Tell the user where the restore point is.

1. **Register the repo (two calls).** Call
   `register_app({ name, repo, description, type, members, accept_guardrails: true })`
   with the app name from Phase 1 and the user's existing `owner/repo` slug (a
   **slug, not a URL**). The first call returns text beginning
   `Registration started …` with an **App install link** — give it to the user
   and have them **install the platform GitHub App** on the account/org that
   owns the repo, scoped to that repository. (The repo already exists, so ignore
   the response's "create from template" note.) Once they've installed it, call
   `register_app` **again with the same arguments**; the second call binds the
   repo and returns the app URL and a `deploy.yml`. Branch on the response the
   same way `inno-new-app` §3 documents (`repo_already_registered`,
   `app_limit_reached`, `repo_mismatch`, `guardrails_not_accepted`, …).
2. **Add the caller workflow.** Write `.github/workflows/deploy.yml` exactly as
   `register_app` returned it (an existing non-template repo won't have one). It
   references `dlaporte/inno-platform-ci/.github/workflows/platform-ci.yml@main`
   and passes `with: app: {name}`; keep its `workflow_dispatch` trigger (the
   platform re-dispatches it for security respins). It is a thin caller — editing
   it can't bypass any gate (the broker's OIDC `job_workflow_ref` check enforces
   provenance), only break the deploy.
3. **Make the repo contract-compliant** — in place, per
   `inno-platform-conventions` (and `inno-containerize` for a container):
   - App code under **`app/`**; entrypoint listens on **8080** and serves
     **`/healthz`** (container) or is `app/index.ts` exporting a `fetch` handler
     (worker).
   - **Auth deleted**; identity read from `X-Forwarded-User` (Python container:
     the reference `current_user(request)` helper).
   - **Persistence rewired** to the storage endpoints (container) or the app's
     `env.DATA`/`env.FILES` bindings (worker).
   - **Dependencies** pinned in the stack's manifest under `app/`, CVE-clean.
   - **Dockerfile** (container) written per `inno-containerize` for the app's
     actual runtime.
   - A root **`CLAUDE.md`** carrying the required section headers (copy
     `dlaporte/inno-template`'s and rewrite the body to describe this app's real
     stack — only the headers are gate-checked).
   - **Remove any forbidden files** flagged in Phase 1 (root
     `package.json`/lockfile/`tsconfig.json`, `src/gateway/`, `wrangler.*`,
     `.env*`, `.npmrc`/`.yarnrc`).
   - Delete `app/.needs-build` if the repo carries one (CI skips deploys while
     it's present).
4. **Secrets in history** — because this is the same repo, a credential in any
   past commit still trips the `secrets` gate. Rotate it (a history rewrite
   alone doesn't un-leak it) and scrub it from history before shipping.
5. **Rewrite `README.md`** to describe the migrated app (what it does, who it's
   for, its URL), drawing on the existing README. Platform mechanics stay in
   `CLAUDE.md`, not here.

## Hand off

End the same way `inno-new-app` does: the next steps are `inno-safety-preflight`
locally, then `inno-ship` — don't commit or push unless asked. If gates fail
after pushing, map the failing job through `inno-ship`'s table. If the user
abandons the migration after registering, point at `inno-manage-app` (`stop_app`)
so the app winds down; uninstalling the GitHub App also unlinks and stops it.
