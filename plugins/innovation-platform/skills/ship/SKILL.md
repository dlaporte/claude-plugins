---
name: ship
description: Use when the user is ready to deploy an inno-{app} — commits, pushes to main, follows CI, and reports the live URL. Use after preflight has passed locally.
---

# ship

Run `preflight` first if it hasn't already passed locally in this session —
`ship`'s job is committing, pushing, and watching CI, not re-deriving whether
the code is clean.

## 0. Precondition — the app must actually be built

If `app/.needs-build` still exists in the repo, STOP — this app is still the
untouched template scaffold. Pushing it deploys nothing (CI's `scaffold-check`
skips the deploy job by design). Tell the user plainly, e.g. "This app hasn't
been built yet — let's add your actual app before shipping," and hand back to
`new-app`/`migrate-app` (or help them build it). Do not delete the marker just
to force a deploy of an empty scaffold.

```bash
test -f app/.needs-build && echo "BLOCKED: app/.needs-build present — build the app first" || echo "OK: no scaffold marker"
```

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
`gh run view <run-id>`.

The pipeline runs five gate jobs in parallel — `config-integrity`, `secrets`
(gitleaks), `sast` (semgrep), `deps` (pip-audit + npm audit), `container`
(docker build + Trivy + non-root/port checks) — and `deploy` only runs if
**all five** succeed (`needs: [config-integrity, secrets, sast, deps,
container]`).

### On failure — fix quietly, report plainly

The user is not necessarily a developer. **Do not paste raw CI logs, stack
traces, or job internals into the conversation.** Read the logs yourself to
diagnose — `gh run view <run-id> --log-failed` — but keep that output to
yourself. To the user, say only a one-line, plain-language status: e.g.
"The security check found an out-of-date dependency — I'm updating it and
re-running." Then fix the **root cause** (never just retry) and push again
(back to step 1).

Use this table to map a failing job to the fix — this is *your* internal
guide, not something to recite to the user:

| Failing job | Likely cause | Fix via |
|---|---|---|
| `config-integrity` | edited `src/gateway/`, `package.json`, lockfile, `tsconfig.json`, or added a stray `wrangler.json`/`.wrangler/` | `platform-conventions` |
| `secrets` | gitleaks found a committed credential | `preflight` (rotate + scrub history) |
| `sast` | semgrep OWASP finding in `app/` | `platform-conventions` (escaping, SQL) |
| `deps` | CVE in `app/requirements.txt` or a prod npm dep | `preflight` |
| `container` | Trivy CVE, root user, or missing `EXPOSE 8080` | `containerize` |

A gate failure is real signal; there is no override or admin bypass.

### When you're stuck — offer to send it to the platform team

If the same gate still fails after **two** genuine root-cause fix attempts (or
you hit something you can't resolve — infrastructure, the deploy broker, a
failure the table doesn't cover), stop retrying. Give the user a short,
plain-language summary of what's wrong, then **ask permission** to send the
details to the platform team for review:

> "I've hit a snag I can't fix from here: <one plain sentence>. Would you like
> me to send the error details to the platform team so they can take a look and
> follow up?"

If they agree, call the **`report_issue`** MCP tool with the app `name`, a
plain-language `summary`, and the raw failing logs you gathered as `logs`
(that's exactly what `--log-failed` is for — it's stored for the team, not
shown to the user). Then relay the reference id the tool returns and let the
user know the team will follow up. Never send logs without the user's OK.

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
