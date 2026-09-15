---
name: inno-safety-preflight
description: Use when the user wants their inno-{app} checked before shipping ("run the safety preflight", "is this safe to ship?", "check my app"). Pushes to main — which runs the platform's REAL safety gates and deploys nothing — then narrates the results with realtime guidance, plus a guardrails policy review. A failure or guardrails violation is a hard stop before inno-ship.
---

# inno-safety-preflight

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

Deploys are release-driven on this platform: **a push to main runs every
safety gate and deploys nothing**. That run — on the platform's own runners,
with the exact pinned tool versions and the admin-configured gate policy — IS
the preflight. Never install or run scanners locally: local results drift
from CI's and know nothing about centrally-configured ignores or gate
toggles.

**Know the policy that applies to THIS app before you narrate anything.** Call
`get_config app=<name>` — the app's owner can read it, no admin needed. It
gives you the actual `safety.gate.*` toggles, the `safety.min_release_age_days`
cooldown in force, and any `safety.ignore.<semgrep|trivy|deps>.<id>`
suppression written at this app's own scope, platform-wide ones being withheld
by design. An ignore's VALUE is its expiry date (`YYYY-MM-DD`, honored
through that day; empty means it never expires), and `get_config` spells the
live state out on the row: suppressing until that date, suppressing with no
expiry, or expired and no longer suppressing. The provenance lines under it
name the admin who set it and whatever note they left. Read it, don't assume
the defaults: a gate an admin turned off still runs as a job and reports
success, logging a loud `SAFETY GATE DISABLED` warning instead of scanning. For
`gitleaks`, `semgrep` and `deps` that means nothing is scanned at all. The
`trivy` toggle is narrower, because it skips only the image CVE scan: the
container job still builds the image, uploads the SBOM, and asserts a non-root
user and `EXPOSE 8080`. And a finding you expect to fail may be suppressed
until a date that has since passed. Two things this buys you: you stop reading
a green gate as proof that a scan actually happened, and you can tell a user
"that CVE is ignored until 2026-12-31, after which this deploy stops passing"
while there's still time to act.

Four things are checked here, and **all are hard requirements before
`inno-ship`**:

1. The **safety gates** (CI) — seven jobs, all `needs:` prerequisites of
   `deploy`, plus the `policy` job that fetches the admin gate policy:
   `config-integrity`, `secrets` (gitleaks), `sast` (Semgrep, over the whole
   repository except the platform-owned root `src/` and the directories
   semgrep skips by default at any depth, `test/`, `tests/`, `build/`, `dist/`,
   `vendor/` and `node_modules/`; `app/`, the Dockerfile,
   `.github/workflows/deploy.yml` and root scripts are all scanned), `deps`
   (dependency audit), `dep-age` (the dependency-release-age cooldown — see
   the table below), `container` (build + image CVEs + non-root/`EXPOSE 8080`
   + a `GET /healthz` smoke test, run for `container` and `mcp-container`
   apps — the image checks are skipped for the function-shaped `function` and
   `mcp-function` types; the image scan runs with `--ignore-unfixed`, so only
   HIGH/CRITICAL findings that have a fix available can fail it), and
   `scaffold-check` (suppresses deploy while the `app/.needs-build` template
   marker is still present).
2. The **guardrails policy** (you): a qualitative read of the app against
   the platform's acceptable-use policy.
3. The **application contract** (you): the app's conformance to the
   platform's runtime requirements that CI can't see.
4. The **app-code security notes** (you): the app-level risk classes the
   perimeter can't close — authorization/IDOR above all.

## 1. Guardrails + contract + security review (do this while CI runs, or first)

Call the `get_guardrails` MCP tool and re-read the app against it — name,
stated purpose, what the code actually does, and how it handles data. You
have the whole repo in front of you; this is judgment, not grep.

- **Clean** → say so in one line and move on.
- **Violation** → HARD STOP. Name the specific policy line, explain the
  conflict plainly, and do not proceed to `inno-ship` until the app is
  changed or the user has an explicit admin exception (they arrange that
  with a platform admin — you cannot grant it). This applies even if every
  CI gate is green.

Then call the `get_app_contract` MCP tool and judge the app against the
MUSTs — focusing on what CI cannot judge for itself: identity read
only from the gateway headers with no home-grown auth (R3), a sign-out link
targeting the team-domain logout (R4, not applicable to `mcp-function` and
`mcp-container` apps: they have no browser session to end), durable state in
the platform stores rather than local disk or memory (R5/R6),
and no reliance on unsupported patterns (background work, machine-to-machine
callers, connections that must survive sleep). `/healthz` (R2) is
CI-enforced — the `container` job smoke-tests it — but CI only sees that it
answers 200 inside the image, so still read it for the parts CI can't:
cheap, no side effects, and **independent of storage**. A contract violation
is the same hard stop as a guardrails one: name the requirement, fix or
guide the fix, re-check.

Finally, for any app with **per-user data, an admin surface, a state-changing
write, or a call to a paid/external upstream**, call the `get_app_security`
MCP tool and review the app's code against it. CI's scanners catch injection
patterns and known-vulnerable deps, but the highest-impact app bug —
**authorization / IDOR** — is invisible to them: verify every query for
user-owned data is scoped by the caller's `X-Forwarded-User` (not by an id
from the request), privileged surfaces gate on a role the app keeps itself
(keyed on `X-Forwarded-User`; `X-Forwarded-Groups` carries only the app's own
`inno-{app}-users` and `inno-{app}-open`, so it can tell a member from an
open-access visitor and nothing finer), values bind
in SQL, output is escaped, and expensive actions are bounded per caller. A
real authorization hole is a hard stop — fix or guide the fix before
`inno-ship`. (A stateless single-view tool can skip this.)

## 2. Push and watch the gates

Before pushing, look at `.github/workflows/deploy.yml`. If it has a
`secrets: inherit` line (repos made from older copies of the template do), the
`sast` gate will fail on it: tell the user, and with their okay delete that
line as part of this push. Nothing else in the file changes.

```bash
git add -A && git commit -m "<why-focused message>"   # if uncommitted work
git push origin main
```

Nothing deploys from this push. Watch the run either way:

- **MCP (no gh needed):** call `get_ci_status` with the app name — it returns
  the run status, the run link, and each gate's conclusion. It also tries for
  file:line failure annotations, but those are best effort: reading them needs
  the GitHub Checks API, and the platform's GitHub App deliberately omits that
  permission, so for a registered app the tool reports the findings as
  unavailable and points at the run link instead. Narrate from the job
  conclusions and that link when that happens.
  Poll every ~30s while `in_progress`; narrate transitions ("secrets ✓,
  container still building…"). Platform tool calls are capped at 60 a minute
  per signed-in user, shared by every agent that user runs; a call over the
  cap answers `rate_limited`. Polling every ~30s is well inside it, but if you
  see `rate_limited`, make no platform call for a full minute, and never poll
  the same run from several subagents at once.
- **gh CLI (if authenticated):** `gh run watch` from the repo.

## 3. Translate the results — this is the actual product

For each gate, tell the user what happened in THEIR terms:

| Outcome | What you say / do |
|---|---|
| All green | "All safety gates passed — `/inno-ship` when you're ready to release." |
| **Real finding** (SAST/deps/CVE) | Show the file:line if the annotations came through. If they didn't, open the run link yourself (or run `gh run view --log-failed` when the user has `gh` authenticated) and read the failing step. Explain the risk in one sentence, fix it (or guide the fix), re-push. |
| **Likely false positive** | Never work around it in code (renames, string-splitting, suppression comments). Name the exact finding ID and tell the user a platform admin can add a central ignore for it (`safety.ignore.<tool>.<id>`, where the value is the expiry date, or empty for none), which clears it at both the gate and the periodic safety sweep. A `secrets` finding is the exception: gitleaks has no central ignore family, because its fingerprints are commit-bound and rebase-fragile. Its supported suppression surface is a `.gitleaksignore` committed in the app's own repo, and an entry there is sanctioned, not an in-code workaround. Semgrep has no repo-side escape at all: from platform v0.14.4 (contract version 13) the `sast` gate ignores `# nosemgrep` comments and deletes every `.semgrepignore` before it scans, so neither hides a finding. A semgrep finding is either fixed in the code (when it is real) or ignored centrally by a platform admin (`safety.ignore.semgrep.<rule id>`). |
| `yaml.github-actions.security.secrets-inherit` finding on `.github/workflows/deploy.yml` | A real fix, not a false positive: tell the user and, with their okay, delete the `secrets: inherit` line from `deploy.yml`. The platform's reusable workflow needs no inherited secrets (it uses only the automatic `GITHUB_TOKEN` and OIDC), and repos made from older copies of the template carry that line. Keep the `workflow_dispatch` trigger. |
| `SAFETY GATE DISABLED by platform policy` in the log | Deliberate admin configuration, not a bug. Note it and move on. |
| config-integrity failure | Something in the repo is a file the platform injects at build time, or one it forbids outright. If the gate names files under a root `src/` directory, stop and show the user what is there before touching anything: the platform owns all of `src/`, not just `src/gateway/`, but that directory can hold the author's own code, so never move or delete anything in it unprompted. With the user's okay, MOVE their code into `app/` (for example `app/src/`), update the Dockerfile `COPY` paths and any imports or build settings that pointed at the old location, and delete only what they confirm is not theirs (a vendored `src/gateway/`, a `src/node_modules/`). A root `package.json`, `package-lock.json` or `tsconfig.json` gets the same care: in a migrated Node repo it can be the app's real manifest, and deleting it breaks the build. Show it to the user and, with their okay, move it under `app/` (updating the Dockerfile `COPY` paths and any scripts or imports that read it); delete it only if they confirm it is not theirs. Delete a root `wrangler.jsonc`. Delete any competing wrangler config (`wrangler.json`, `wrangler.toml`, an env variant), which wrangler's config discovery could let outrank the vetted file, and a `.wrangler/` directory, whose `deploy/config.json` can redirect the deploy to an unvetted config entirely. Delete a `scaffold/` directory, which registration prunes out of app repos, unless `app/.needs-build` is still present (the check is waived until that marker goes). Remove a root-level `.env*` and any root package manager config (`.npmrc`, `.yarnrc`, `.yarnrc.yml`, `.pnpmfile.cjs`, `pnpm-workspace.yaml`, `bunfig.toml`); a `.env`'s values move into app Variables with `set_app_variable`. Remove every `.npmrc` at any depth, `app/.npmrc` included: npm expands environment variables into it, so it is rejected wherever it sits. If instead `CLAUDE.md`'s required template headers were altered, revert them (the rest of the file is yours). A message that the gate "could not fully inspect the app tree" means a committed directory it could not read; fix or remove that path. Everything else under `app/` (an `app/package.json`, an `app/.yarnrc.yml`, an `app/src/`) is yours and fine. |
| `dep-age` failure | The **inverse** of a CVE finding: do NOT bump to the newest release, that makes it redder. Either a pinned dependency was published more recently than the platform's cooldown allows (`safety.min_release_age_days`, 0 = off and the default, so this only fires once an admin has enabled it; `get_config app=<name>` tells you the value actually in force and how many days you're short by), or the app ships `app/package.json` with no committed, parseable `app/package-lock.json` and there are no exact versions to date at all. Remedies: wait out the cooldown, pin an older vetted version, commit `app/package-lock.json`, or ask a platform admin for an app-scope `safety.min_release_age_days: 0`. Separately from this gate, a function-shaped app's release fails without a committed `app/package-lock.json` whatever the cooldown says (platform v0.14.2). |
| container failure | Dockerfile contract problem, or the built image never answered `GET /healthz` within ~90s; hand off to `inno-containerize`. For a non-root failure: the gate accepts only a plain uid 1 to 2147483647 or a portable name on one clean `/etc/passwd` line (see `inno-containerize` item 2). The image this job scans on the tag run is the exact image that ships: the deploy job pushes it by digest and never rebuilds the Dockerfile. |

Diagnose privately (the `get_ci_status` run link and job conclusions, its
annotations when they come through, or `gh run view --log-failed` if the user
has `gh` authenticated); don't paste raw logs at the user. After two failed
fix attempts on the same gate, ask permission to create a
`create_support_bundle` for the app and hand the user the download link to
attach to a support ticket. Each app is limited to 5 bundles in any rolling
24 hours: if the tool answers `bundle_limit_reached`, do not retry; point the
user at a bundle already created (they cover the same recent window), or wait
for the oldest to age out.

## Done

End with a clear verdict: **"Safe to ship"** (gates green and guardrails
clean, and, for a `function` or `mcp-function` app that has
`app/package.json`, a committed `app/package-lock.json` in step with it; point
at `/inno-ship`) or **"Not yet"** with the specific blockers listed. Check that
lockfile yourself before saying "Safe to ship": the push-time `deps` gate
builds a throwaway lockfile when none is committed, so its green does not
prove the tagged deploy, which runs `npm ci` and fails without one.
