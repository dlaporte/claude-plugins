---
name: ship
description: Use when the user is ready to deploy an inno-{app} — commits, pushes to main, follows CI, and reports the live URL. Use after preflight has passed locally.
---

# ship

Run `preflight` first if it hasn't already passed locally in this session —
`ship`'s job is committing, pushing, and watching CI, not re-deriving whether
the code is clean.

## 1. Commit and push to `main`

```bash
git add -A
git commit -m "<short, why-focused message>"
git push origin main
```

Every `inno-{app}` repo's `.github/workflows/deploy.yml` is a thin caller
that triggers on `push: branches: [main]` — there's no separate release step,
a push to `main` **is** the deploy trigger.

## 2. Watch CI

```bash
gh run watch
```

Or, if you'd rather poll manually: `gh run list --limit 1`, then
`gh run view <run-id>`. On any job failure, get the actual log rather than
guessing from the job name:

```bash
gh run view <run-id> --log-failed
```

The pipeline runs five gate jobs in parallel — `config-integrity`, `secrets`
(gitleaks), `sast` (semgrep), `deps` (pip-audit + npm audit), `container`
(docker build + Trivy + non-root/port checks) — and `deploy` only runs if
**all five** succeed (`needs: [config-integrity, secrets, sast, deps,
container]`). Map a failing job back to the relevant skill:

| Failing job | Likely cause | Fix via |
|---|---|---|
| `config-integrity` | edited `src/gateway/`, `package.json`, lockfile, `tsconfig.json`, or added a stray `wrangler.json`/`.wrangler/` | `platform-conventions` |
| `secrets` | gitleaks found a committed credential | `preflight` (rotate + scrub history) |
| `sast` | semgrep OWASP finding in `app/` | `platform-conventions` (escaping, SQL) |
| `deps` | CVE in `app/requirements.txt` or a prod npm dep | `preflight` |
| `container` | Trivy CVE, root user, or missing `EXPOSE 8080` | `containerize` |

Fix the root cause, don't just retry the run — then commit and push again
(back to step 1). A gate failure is real signal; there is no override or
admin bypass for these jobs.

## 3. On success — provenance, then the live URL

If all gates pass, the `deploy` job requests a GitHub OIDC token (audience
`inno-platform-deploy`) and exchanges it with the platform's deploy broker
for a scoped Cloudflare deploy token. The broker's guarantee is what makes
the whole gate structure non-bypassable: it verifies the OIDC token's signed
`job_workflow_ref` claim equals exactly
`dlaporte/inno-platform/.github/workflows/platform-ci.yml@refs/heads/main`
— i.e. that the run actually executed the platform's *reusable* workflow
(which an app author cannot edit) from `main`, not some stripped-down or
forked copy of the caller workflow. **A repo whose deploy.yml is edited to
skip gates, or that runs the workflow from a fork/branch, gets a `403
deploy_denied` from the broker** — there is no code path where removing the
gates yields a working deploy.

On a genuine success, report to the user:

```
Deployed: https://inno-{name}.davidlaporte.org
```

and note that the app is **Okta-gated** — the first visit prompts an
Okta login (Cloudflare Access), and only the owner plus anyone
granted access via `manage-app`'s `grant_access` can reach it.
