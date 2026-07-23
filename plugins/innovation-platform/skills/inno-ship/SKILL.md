---
name: inno-ship
description: Use when the user is ready to release an inno-{app} — pushes, waits for the safety checks, cuts the v* release tag that actually deploys, and reports the live URL. Use after inno-safety-preflight is clean (gates AND guardrails).
---

# inno-ship

Deploys are **release-driven**: a push to main runs the safety gates and
deploys nothing; **tagging a `v*` release is what deploys**. This skill makes
that seamless — for a less-technical user, "shipping" is one conversation and
the versioning just happens.

Run `inno-safety-preflight` first if it hasn't passed in this session. Its
verdict covers BOTH the safety gates and the guardrails policy review — if
the guardrails review flagged an unresolved violation, **do not ship**, even
with green gates, until it's resolved or the user has an admin exception.

## 0. Precondition — the app must actually be built

If `app/.needs-build` still exists in the repo, STOP — this app is still the
untouched template scaffold. Tell the user plainly, e.g. "This app hasn't
been built yet — let's add your actual app before shipping," and hand back to
`inno-new-app`/`inno-migrate-app` (or help them build it). Do not delete the
marker just to force a release of an empty scaffold.

```bash
test -f app/.needs-build && echo "BLOCKED: app/.needs-build present — build the app first" || echo "OK: no scaffold marker"
```

## 1. Commit, push, and wait for green checks

```bash
git add -A
git commit -m "<short, why-focused message>"
git push origin main
```

This runs the six gate jobs (`config-integrity`, `secrets`, `sast`, `deps`,
`container`, plus the policy fetch) and **stops** — the deploy job is
ref-gated to release tags. Watch with `gh run watch` or the `get_ci_status`
MCP tool. If a gate fails, follow the failure guidance below and re-push;
never tag on top of red checks.

## 2. Cut the release — this is the deploy

Pick the version, then tag:

```bash
git fetch --tags
git tag --list 'v*' --sort=-v:refname | head -3   # what's the latest release?
git tag v<X.Y.Z>
git push origin v<X.Y.Z>
gh release create v<X.Y.Z> --verify-tag --title "v<X.Y.Z> — <short description>" \
  --notes "<one bullet per commit subject since the last tag>"
```

A bare tag deploys but leaves the repo's **Releases** page empty — always
create the GitHub Release too (after the tag push; creating a release on an
already-pushed tag does not re-trigger the deploy).

Version selection: default to a **patch** bump of the latest `v*` tag; use a
**minor** bump when this ships a user-visible feature; `v1.0.0` for a first
release. Only ask the user if it's genuinely ambiguous — otherwise just tell
them what you're doing ("shipping v1.2.0"). The tag push re-runs the gates on
the tagged commit and then deploys.

## 3. Watch the release run

```bash
gh run watch    # or poll get_ci_status
```

### On failure — fix quietly, report plainly

The user is not necessarily a developer. **Do not paste raw CI logs, stack
traces, or job internals into the conversation.** Read the logs yourself
(`gh run view <run-id> --log-failed`) but keep that output to yourself. To
the user, one plain sentence: "The security check found an out-of-date
dependency — I'm updating it and re-shipping." Fix the **root cause**, push,
and cut the next patch tag (a tag is immutable — never force-move one).

| Failing job | Likely cause | Fix via |
|---|---|---|
| `config-integrity` | repo contains a platform-injected file that must not exist — `src/gateway/`, `package.json`, `package-lock.json`, `tsconfig.json`, or `wrangler.jsonc` (delete it; the platform injects all of these at build time) — or added a stray `wrangler.json`/`.wrangler/` or a root-level `.env*`/`.npmrc`/`.yarnrc` | `inno-platform-conventions` |
| `secrets` | gitleaks found a committed credential | rotate + scrub history |
| `sast` | semgrep OWASP finding in `app/` | `inno-platform-conventions` (escaping, SQL) |
| `deps` | CVE in `app/requirements.txt` or a prod npm dep | bump the pinned dep |
| `container` | Trivy CVE, root user, or missing `EXPOSE 8080` | `inno-containerize` |
| `deploy` fails with `app_stopped` | the app was stopped by the lifecycle (or deliberately) — **stopped apps cannot be deployed** | `inno-manage-app`: `start_app` first, then re-tag |

A gate failure is real signal; there is no override or admin bypass. A
finding that's a false positive gets a **central admin ignore** (see
`inno-safety-preflight`), never an in-code workaround.

### When you're stuck — offer to send it to the platform team

If the same gate still fails after **two** genuine root-cause fix attempts,
stop retrying. Summarize plainly, then **ask permission** to send details to
the platform team via the **`report_issue`** MCP tool (app `name`,
plain-language `summary`, the raw failing logs as `logs`). Relay the
reference id it returns. Never send logs without the user's OK.

## 4. On success — provenance, then the live URL

The `deploy` job (tag runs only) requests a GitHub OIDC token (audience
`inno-platform-deploy`) and exchanges it with the platform's deploy broker
for a scoped Cloudflare deploy token. The broker verifies the token's signed
`job_workflow_ref` claim equals exactly
`dlaporte/inno-platform/.github/workflows/platform-ci.yml@refs/heads/main`
and that the triggering ref is `main` or a `v*` tag — a repo whose deploy.yml
is edited to skip gates, or that runs from a fork/branch, gets `403
deploy_denied`. There is no code path where removing the gates yields a
working deploy. The release tag is recorded on the deployment — the platform
shows it, and the safety sweep's auto-respin rebuilds at exactly that tag.

On success, report:

```
Shipped v<X.Y.Z> — <the app URL, as reported by app_status / create_app>
```

and note that the app is **Okta-gated** — the first visit prompts an Okta
login (Cloudflare Access), and only the owner plus anyone granted access via
`inno-manage-app`'s `grant_access` can reach it.

### Do not curl, dig, or otherwise resolve the hostname to "verify" success

Never look up `inno-{name}.davidlaporte.org` yourself (via `curl`, `dig`,
`nslookup`, a browser navigation, etc.) as a way to confirm the deploy
worked — especially right after a first-ever deploy for a brand-new app. The
DNS record for a freshly deployed hostname can take up to roughly a minute to
propagate, and any tool commands you run execute on the user's own machine,
sharing their real network stack — not an isolated sandbox. A lookup that
lands in that propagation window gets a negative (NXDOMAIN/SERVFAIL) answer,
and that negative result can get cached independently in multiple places
(the user's router-level DNS resolver, e.g. AdGuard Home/Pi-hole, and their
OS's local resolver cache, e.g. macOS `mDNSResponder`) for minutes — making
the app look broken to the user long after it actually went live, and it
won't self-correct until each cache's negative TTL expires or someone
manually flushes it.

The `deploy` job's success/failure and the `app_status` MCP tool's
deployment timestamp are the authoritative, side-effect-free signals — use
those. If the user wants to see the app for themselves, let them visit it
in their own browser; don't pre-check it for them.
