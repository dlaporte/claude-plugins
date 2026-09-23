---
name: inno-ship
description: Use when the user is ready to release an inno-{app} — pushes, waits for the safety checks, cuts the v* release tag that actually deploys, and reports the live URL. Use after inno-safety-preflight is clean (gates AND guardrails).
---

# inno-ship

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

If the line reads **current** but adds that a newer version **is available**,
that is advisory, not a block: mention it once, with the same two commands, and
carry on with the skill.

If there is no `Plugin:` line at all, the gate is not armed on this platform.
Carry on.

Deploys are **release-driven**: a push to the default branch runs the safety
gates and deploys nothing; **tagging a `v*` release is what deploys**. This
skill makes that seamless: for a less-technical user, "shipping" is one
conversation and the versioning just happens.

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

For a function-shaped app (`function`, `mcp-function`), also confirm the
lockfile. The push checks do catch its absence, in the `app-deps` job; the
rule they enforce is `inno-platform-conventions`' **Node apps** paragraph.
Check it here anyway, as belt, to save a round trip through CI:

```bash
if [ -f app/package.json ] && [ ! -f app/package-lock.json ]; then echo "BLOCKED: commit app/package-lock.json (run npm install inside app/)"; else echo "OK: lockfile present, or no app/package.json"; fi
```

Then, only when `app/package.json` exists, install from the lockfile exactly as
the `app-deps` job does. A function app with no `app/package.json` has no
dependencies and nothing to install; do not create one to satisfy npm. The
install creates `app/node_modules/`, which must be gitignored before §1's
`git add -A` (template repos already ignore it; a migrated repo may not):

```bash
if [ -f app/package.json ]; then
  (cd app && npm ci --ignore-scripts --omit=dev) && { git check-ignore -q app/node_modules/ || echo "BLOCKED: add node_modules/ to .gitignore before git add -A"; }
else
  echo "OK: no app/package.json, so nothing to install"
fi
```

Every package the code imports must be declared in `app/package.json` under
`dependencies`, because `app-deps` installs from that file alone, with
`--omit=dev`, and nothing is installed at the repo root.

### Declared variables, if the app has any

If the repo has `app/inno-variables.json`, read it before tagging: nothing
in CI validates or applies it before the tag's `deploy` job finalizes, so
this is the only check that helps before the first deploy. It must be a
JSON object keyed by variable name (env-var shaped:
`^[A-Z][A-Z0-9_]{0,63}$`, and not one of the platform-reserved names or
prefixes: `ENVIRONMENT`, `SLEEP_AFTER`, `ACCESS_TEAM_DOMAIN`, `ACCESS_AUD`,
`OAUTH_RS_MODE`, `OAUTH_RS_RESOURCE`, `MCP_AUTH_SERVER`, `PORT`, `DATA`,
`FILES`, `DB`, `APP`, `APP_WORKER`, `PLATFORM`, or a `LINKED_`/`APPVAR_`
prefix), each value an object with only `required` (bool, default false),
`secret` (bool, default true) and `description` (string, ≤200 chars,
default empty): an unrecognized field name, a wrong-typed field, a bad
name, or more than 32 entries refuses the **whole file** (the platform keeps
its previous declarations and the tag still deploys; the reason surfaces
only on the `deploy-complete:` line in this run's log). A file that is not
valid JSON, cannot be read, or is over 32 KB never reaches the platform at
all. That class does not fail the deploy either: the run prints a
`::warning title=Declared variables::` annotation naming the reason, sends
no declarations, and then finalizes as usual, so the `deploy-complete:` line
still appears, just with no `variables_refused` field on it. Look for the
warning annotation, not for a missing line. For every name
marked `required: true`, call `list_app_variables` (or read `app_status`,
which now names an unset required one on its own line) and tell the user
before you tag if it has no value yet: the platform never blocks a deploy
or fails a gate over a missing required variable, so this is the only
warning the user gets before finding out at runtime.

## 1. Commit, push, and wait for green checks

**Confirm the branch before pushing**, exactly as `inno-safety-preflight` §2
says (the gates run only on pushes to the repository's default branch).

```bash
git add -A
git commit -m "<short, why-focused message>"
git push origin HEAD
```

Between the `git add -A` and the commit, run the **directory-symlink check**
from `inno-safety-preflight` §2. It has one copy in this plugin and lives
there; a committed directory link fails `config-integrity` with no policy
toggle, and it has to run after `git add -A` so the index covers both
already-tracked links and the ones you are about to commit.

This runs the eight gate jobs (`config-integrity`, `secrets`, `sast`, `deps`,
`dep-age`, `container`, `scaffold-check`, `app-deps`) plus the `policy` fetch
that resolves the admin gate configuration, and then **stops** — the deploy job is
ref-gated to release tags. The `container` image gates run for `container` and
`mcp-container` apps; they're skipped for `function` and `mcp-function` apps,
which have no image to build. Watch with `gh run watch` or the `get_ci_status`
MCP tool, and read `get_ci_status` (which run it is, its annotations, its two
refusals) as `inno-safety-preflight` §2 says. If a gate
fails, follow the failure guidance below and re-push; never tag on top of red checks.

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

If you poll `get_ci_status` instead, wait at least 30 seconds between calls,
and never poll the same run from several subagents at once: the platform's
call budget is per person, not per agent. The rule is `inno-manage-app`'s
**Call budget** section.

### On failure — fix quietly, report plainly

The user is not necessarily a developer. **Do not paste raw CI logs, stack
traces, or job internals into the conversation.** The same goes for
technology names: say "the security check", "the database", "file storage",
per the plugin README's **House style** section. Read the logs yourself
(`gh run view <run-id> --log-failed`) but keep that output to yourself. To
the user, one plain sentence: "The security check found an out-of-date
dependency — I'm updating it and re-shipping." Fix the **root cause**, push,
and cut the next patch tag (a tag is immutable — never force-move one).
The exception: before any fix that moves, deletes or replaces the user's
files, or edits anything under `.github/workflows/`, show the user the change
and ask first, whether or not the row below says so.

| Failing job | Likely cause | Fix via |
|---|---|---|
| `config-integrity` | the repo carries a platform-owned or forbidden path, or `CLAUDE.md` lacks a required header. The failure message names each path; the full list, with the reason for each, is `inno-platform-conventions`' **Files you must not touch** section | **stop and ask; this is not a quiet fix.** Files under `src/` and a root `package.json` can be the user's own code: show the user every flagged path first. Only with their okay, move author code and manifests under `app/` (for example `app/src/`), update the Dockerfile `COPY` paths and the code's imports to match, and delete only what they confirm is not theirs (such as `src/gateway/` or `src/node_modules/`). Never move or delete author code unprompted before a tagged deploy. See `inno-platform-conventions` |
| `secrets` | gitleaks found a committed credential | rotate + scrub history, then set the new value as an app Variable (`set_app_variable`) |
| `sast` | a semgrep OWASP finding anywhere the gate scans, which is the whole repository and not just `app/` (the scope is `inno-platform-conventions`' **Rendering** section; the log names the file). A `secrets: inherit` line in `.github/workflows/deploy.yml` (older template copies carry one) is a blocking finding too | `inno-platform-conventions` (escaping, SQL); for `secrets: inherit`, tell the user and, with their okay, delete the line (the platform workflow needs no caller secrets) |
| `deps` | CVE in `app/requirements.txt` or a prod npm dep. `npm audit` runs `--omit=dev`; since platform v0.14.21, and contract version 21 states it, `app-deps` installs with `--omit=dev` too, so the audited set and the installed set are the same, and a devDependency is never installed either | bump the pinned dep |
| `dep-age` | a pinned dep is **too new** for the platform's release-age cooldown (`safety.min_release_age_days`; off by default, so this only fires once an admin enabled it), or `app/package.json` ships with no committed, parseable `app/package-lock.json` so there is nothing to date | **not** a version bump — bumping to the newest release makes it worse. Wait out the cooldown, pin an older vetted version, commit `app/package-lock.json`, or ask a platform admin for an app-scope `safety.min_release_age_days: 0` |
| `container` | Trivy CVE, a `USER` the non-root gate refuses (the gate accepts only a plain uid 1 to 2147483647 or a portable name on one clean `/etc/passwd` line; see `inno-containerize` item 2), missing `EXPOSE 8080`, or the image never answered `GET /healthz` | `inno-containerize` |
| `scaffold-check` | not a failure — it suppresses `deploy` while `app/.needs-build` exists (see §0) | build the app, remove the marker |
| `deploy` fails with `app_stopped` | the app was stopped by the lifecycle (or deliberately), and **stopped apps cannot be deployed**. Only the release tag's `deploy` job fails this way; a push to the default branch still runs every gate green on a stopped app, so a clean preflight is not evidence that the app can deploy | `inno-manage-app`: `start_app` first, then cut the next patch tag |
| `app-deps` fails with `Missing app/package-lock.json` (function-shaped apps) | `app/package.json` exists but no lockfile is committed; CI installs only from a committed lockfile and never resolves ranges fresh. This job runs on pushes too, so the failure blocks before any tag exists | run `npm install` inside `app/`, commit `app/package-lock.json`, push, confirm `app-deps` is green, then tag |
| `app-deps` fails in `npm ci` (on pushes as well as tags), or the `deploy` bundle step reports `Could not resolve "<package>"` with the titled error `Undeclared import` (function-shaped apps), or reports it with the titled error `devDependency imported at runtime` | the lockfile no longer matches `app/package.json`, or the code imports a package not declared anywhere (nothing is installed at the repo root), or the code imports at runtime a package declared only under `devDependencies` (`app-deps` installs `--omit=dev`, so that tree was never installed) | for an undeclared package: declare it in `app/package.json`, run `npm install` inside `app/`, commit both files, push, confirm `app-deps` is green, then cut the next patch tag. For a devDependency: move it to dependencies instead, `cd app && npm install <package> && npm uninstall --save-dev <package>`, commit `app/package.json` and `app/package-lock.json`, push, confirm `app-deps` is green, then cut the next patch tag |
| `deploy` fails with `app_not_deployable` | the app was stopped, or its repo lost the platform GitHub App, while this deploy was starting | if the repo was unlinked, have the user reinstall the GitHub App on it first (re-linking leaves the app stopped); then `start_app` (`inno-manage-app`) and cut the next patch tag |
| `deploy` fails at finalize with `app_not_deploying` | the app was stopped or purged while the deploy ran; nothing went live | `app_status` to see which; if stopped, `start_app`, then cut the next patch tag |
| `deploy` fails with `No scanned image recorded` (container apps) | the platform has no record of the image this run's `container` job scanned (that job's best-effort SBOM upload failed, or the record could not be read), so the deploy cannot prove which image passed the gates | re-run the whole tag run (`gh run rerun <run-id>`); if it repeats, stop and offer a support bundle |
| `deploy` fails with `Image mismatch`, or finalize refuses `image_mismatch` (container apps) | the image handed to the deploy job is not the one the gates scanned; this is never a code bug. Check that `.github/workflows/deploy.yml` still matches `register_app`'s snippet (one `platform` job, nothing that uploads an artifact named `inno-scanned-image`) | show the user how `deploy.yml` differs from the snippet; with their okay restore it, push, and cut the next patch tag (a re-run of the old tag reuses the old workflow file); if `deploy.yml` already matches, re-run the whole tag run; if it repeats, stop and offer a support bundle |
| the broker refuses `app_mismatch`: a container app's `container` job logs `deploy-sbom failed (403)` naming `app_mismatch`, the `policy` job warns `Gate policy unavailable`, and a tag run's `deploy` stops at `Gateway not promoted` | the repository is registered to a different app than the one `deploy.yml` names: the broker identifies the app from the signed repository id, the `with: app:` value (or, with no `with:` block, the name derived from the repo name) disagrees, and it refuses every request, the policy fetch included. With no policy the gates run all on with no ignores and as a container app, so a function-shaped app shows only the warning and a failed `container` job | with the user's okay, set `with: app:` to the app this repo is registered as (`list_apps` names the repo beside each app), or restore `register_app`'s snippet; push, confirm the gates are green, and cut the next patch tag |
| the broker refuses `repo_unlinked`: the same three signs, the `deploy-sbom failed (403)` line saying the app "is no longer linked to its repository" on a tag run only (the SBOM upload is a deploy-mode call, so on a push the tag-ref check refuses it first and that line reads `deploy_denied:ref`, as it does for every push; `app_mismatch` shows on both) | the platform GitHub App was uninstalled from the repo, or the repo was removed from the installation. The broker issues nothing to an unlinked app, and the app itself is stopped and counting down to purge (`list_apps` flags it `[UNLINKED]`) | have the user reinstall the platform GitHub App on the repo, which re-links it; then `start_app` (`inno-manage-app`), push, and cut the next patch tag |
| `policy` fails with `Invalid app name` | the `with: app:` value in `deploy.yml` is not a valid app name | with the user's okay, correct the `with: app:` value (or restore `register_app`'s snippet), push, cut the next patch tag |

A gate failure is real signal; there is no override or admin bypass. A
finding that's a false positive gets a **central admin ignore** (see
`inno-safety-preflight`), never an in-code workaround. Gitleaks is the one
exception: it has no central ignore family, so a false-positive `secrets`
finding is suppressed with a `.gitleaksignore` entry in the app's own repo.

### When you're stuck — offer to build a support bundle

If the same gate still fails after **two** genuine root-cause fix attempts,
stop retrying. Summarize plainly, then **ask permission** to create a
diagnostics **support bundle** via the **`create_support_bundle`** MCP tool
(`app`, plus a plain-language `description`). Give the user the download link
it returns and tell them to attach the zip to a ticket in the support
system — the platform team triages there, not in the platform.
The caps and refusals are `inno-manage-app`'s support-bundle section; the one
to expect here is `bundle_limit_reached`, and the answer to it is to attach
the most recent existing bundle rather than retrying, since every bundle
covers the same recent window.

## 4. On success — provenance, then the live URL

The `deploy` job (tag runs only) requests a GitHub OIDC token (audience
`inno-platform-deploy`) and exchanges it with the platform's deploy broker
for a scoped Cloudflare deploy token. The broker verifies the token's signed
`job_workflow_ref` claim equals exactly
`dlaporte/inno-platform-ci/.github/workflows/platform-ci.yml@refs/heads/main`
and that the triggering ref is a `refs/tags/v*` release tag — the broker
issues deploy tokens for tags only, so a request from a push to the default
branch, a push to any other branch, or a fork gets `403 deploy_denied`, as
does a repo whose deploy.yml is edited to skip gates. There is no code path
where removing the gates yields a working deploy. The release tag is recorded
on the deployment: the platform shows it, and the safety sweep's auto-respin
rebuilds at exactly that tag.
For a container app the deploy also refuses unless the image it pushes is
exactly the one the `container` job scanned (checked by image id, then pinned
by digest), so what the gates approved is what runs.

On success, report:

```
Shipped v<X.Y.Z> — <the app URL, as reported by app_status / register_app>
```

and note that the app is **Okta-gated** — the first visit prompts an Okta
login (Cloudflare Access), and only the owner plus anyone granted access via
`inno-manage-app`'s `grant_access` can reach it, unless the app has been
opened to every SSO user with `set_app_access` (`inno-manage-app`).

For an **mcp-function** or **mcp-container** app, report the **MCP endpoint** (`…/mcp`, as returned by
`app_status` / `register_app`) instead of a browser URL, and tell the user to
add it as an MCP server in their client (Claude Code, claude.ai) — the first
connection runs an OAuth authorization (consent + Okta) rather than a browser
SSO redirect. Access is still the app's member list, or every SSO user
once the app is opened with `set_app_access`.

**On a brand-new app's first-ever deploy, warn about the propagation window
when you hand over the URL/endpoint — don't just paste a bare link.** The same
DNS propagation window covered below (up to roughly a minute) applies to the
*user's* first click, not just to an agent-run lookup. Say something like:
"it can take up to a minute to resolve — if it doesn't load on the first try,
wait a minute before retrying rather than refreshing or re-clicking
repeatedly." Repeated clicks inside that window are exactly what get the
negative (NXDOMAIN) result cached on the user's own machine for minutes, even
after the app is actually live. This caveat doesn't apply to redeploys of an
already-live app — the hostname already resolves.

Container-shape redeploys (`container`, `mcp-container`): a deploy replaces the
image, but an instance that is actively serving keeps running the OLD image
until it recycles (idle sleep or `restart_app`). If the user redeployed a fix
to a busy app and it still shows old behavior, run `restart_app` — the next
request cold-starts on the new image.

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

### A brand-new app's first health status may briefly read `unknown`, not `unhealthy`

Don't read a still-`unknown` `app_status` right after a first deploy as a
problem: the deploy-time probe defers rather than alarms when it cannot reach
the origin at all, which is exactly what a freshly-attached hostname looks
like while a container finishes cold-starting. The status stays untouched and
clears on the next hourly cron pass. A genuinely broken deploy still surfaces
immediately, because an application-level 5xx is a real answer from a
reachable app and is never deferred.

The probe clocks themselves have one home, `inno-containerize` item 4: which
statuses defer, the 45-second attempt with its single retry, the roughly
95-second verdict, the hourly floor, and `health.probe_interval_hours`. Two
things this skill adds. `restart_app` does **not** re-fire the probe or update
the deployment record, so it will not clear or refresh a pending status. And
to get a fresh signal sooner than the next hourly pass, re-run the whole tag
run (`gh run rerun <run-id>`, without `--job`: a container deploy needs the
image that same run's `container` job scanned, kept for only one day).
