---
name: inno-ship
description: "Use when the user is ready to release an app: pushes, waits for the safety checks, cuts the v* release tag that actually deploys, and reports the live URL. Use after inno-safety-preflight is clean (gates AND guardrails)."
---

# inno-ship

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

Deploys are **release-driven**: a push to the default branch runs the safety
gates and deploys nothing; **tagging a `v*` release is what deploys**. This
skill makes that seamless: for a less-technical user, "shipping" is one
conversation and the versioning just happens.

Run `inno-safety-preflight` first if it hasn't passed in this session. Its
verdict covers BOTH the safety gates and the guardrails policy review: if
the guardrails review flagged an unresolved violation, **do not ship**, even
with green gates, until it's resolved or the user has an admin exception.

**Asking a platform admin.** Where this skill, or its
`references/deploy-failures.md`, sends the user to a platform admin (an
exception, an ignore or a waiver, a shorter release-age cooldown, a fix on
the platform's side), the request goes to the contact the platform names:
the `Support:` line of the status you read in the Version gate, when it has
one. `inno-manage-app`'s **Asking a platform admin** is the one home for
that rule.

## 0. Precondition: the app must actually be built

If `app/.needs-build` still exists in the repo, STOP: this app is still the
untouched template scaffold. Tell the user plainly, e.g. "This app hasn't
been built yet; let's add your actual app before shipping," and hand back to
`inno-new-app`/`inno-migrate-app` (or help them build it). Do not delete the
marker just to force a release of an empty scaffold.

```bash
test -f app/.needs-build && echo "BLOCKED: app/.needs-build present, build the app first" || echo "OK: no scaffold marker"
```

For a function-shaped app (`function`, `mcp-function`), also confirm the
lockfile. The push checks do catch its absence, in the `app-build` job; the
rule they enforce is `inno-platform-conventions`' **Node apps** paragraph.
Check it here anyway, as belt, to save a round trip through CI:

```bash
if [ -f app/package.json ] && [ ! -f app/package-lock.json ]; then echo "BLOCKED: commit app/package-lock.json (run npm install inside app/)"; else echo "OK: lockfile present, or no app/package.json"; fi
```

Then, only when `app/package.json` exists, install from the lockfile exactly as
the `app-build` job does. A function app with no `app/package.json` has no
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

Every package the code imports must be declared under `dependencies` in
`app/package.json`; the rule is the contract's §1.1 **Dependencies** bullet
(`get_app_contract` with `sections: ["1.1"]`).

### Declared variables, if the app has any

If the repo has `app/inno-variables.json`, read it before tagging: nothing
in CI validates or applies it before the tag's `deploy` job finalizes, so
this is the only check that helps before the first deploy. Check it against
the contract's §2.3 **Secrecy.** and **Declaring what an app wants**
paragraphs (`get_app_contract` with `sections: ["2.3"]`): the name rule and
the reserved names from the first, the three allowed fields with their
defaults and their types, and the 32-entry cap, from the second. A file
that breaks them never fails the deploy, and the platform keeps its previous
declarations; the reason shows in one of two places:

- a file the platform refuses: on the `deploy-complete:` line in this
  run's log;
- a file that is not valid JSON, cannot be read, or is over 32 KB, which
  never reaches the platform: a `Declared variables` warning annotation
  (on `app/inno-variables.json`) naming the reason. The `deploy-complete:`
  line still appears, just with no `variables_refused` field on it, so look
  for the warning annotation, not for a missing line.

For every name marked `required: true`, call `list_app_variables` (or read
`app_status`, which names an unset required one on its own line) and tell
the user before you tag if it has no value yet: the platform never blocks a
deploy or fails a gate over a missing required variable, so this is the
only warning the user gets before finding out at runtime. Whether to set it,
or fix the file, before tagging is the user's decision, never a reason for
you to refuse the tag; `inno-safety-preflight` §1b states the same rule.

## 1. Commit, push, and wait for green checks

**Confirm the branch before pushing**, exactly as `inno-safety-preflight` §2
says (the gates run only on pushes to the repository's default branch).

```bash
git add -A
git commit -m "<short, why-focused message>"
git push origin HEAD
```

Between the `git add -A` and the commit, run the **symlink check** from
`inno-safety-preflight` §2. It has one copy in this plugin and lives there;
a committed directory link, dangling link or link out of the repository
fails `config-integrity` with no policy toggle, and the check has to run
after `git add -A` so the index covers both already-tracked links and the
ones you are about to commit.

This runs the eight gate jobs (`config-integrity`, `secrets`, `sast`, `deps`,
`dep-age`, `container`, `scaffold-check`, `app-build`) plus the `policy` fetch
that resolves the admin gate configuration, and then **stops**: the deploy
job runs only on release tags. The `container` job is skipped for
`function` and `mcp-function` apps, which have no image to build; for them
`app-build` installs and bundles the app on every push, holding no
credential, so a build failure shows on the push rather than at the tag.
Watch with
`gh run watch` or the `get_ci_status` MCP tool, and read `get_ci_status`
(which run it is, each failed job's failed step and log lines, its refusals)
as `inno-safety-preflight` §2 says. If a gate fails, follow the failure guidance below and re-push;
never tag on top of red checks.

The `container` job also writes the accessibility, response-header and
Dockerfile reports; `inno-safety-preflight` §1c says where they are and how
to read them. In the default `report` mode their findings never block a
push or a tag, so do not hold a release for them, and do not read a green
`container` job as a clean report either. Only when an admin has set the
app's `safety.a11y.mode` to `enforce` can the accessibility report fail the
job: the `Accessibility check failed` row below.

## 2. Cut the release: this is the deploy

Pick the version, then tag:

```bash
git fetch --tags
git tag --list 'v*' --sort=-v:refname | head -3   # what's the latest release?
git tag v<X.Y.Z>
git push origin v<X.Y.Z>
gh release create v<X.Y.Z> --verify-tag --title "v<X.Y.Z>: <short description>" \
  --notes "<one bullet per commit subject since the last tag>"
```

A bare tag deploys but leaves the repo's **Releases** page empty, so always
create the GitHub Release too (after the tag push; creating a release on an
already-pushed tag does not re-trigger the deploy).

Version selection: default to a **patch** bump of the latest `v*` tag; use a
**minor** bump when this ships a user-visible feature; `v1.0.0` for a first
release. Only ask the user if it's genuinely ambiguous; otherwise just tell
them what you're doing ("shipping v1.2.0"). The tag push re-runs the gates on
the tagged commit and then deploys.

## 3. Watch the release run

```bash
gh run watch    # or poll get_ci_status
```

If you poll `get_ci_status` instead, poll at the cadence `inno-manage-app`'s
**Call budget** section sets.

### On failure: fix quietly, report plainly

The user is not necessarily a developer. **Do not paste raw CI logs, stack
traces, or job internals into the conversation.** The same goes for
technology names: say "the security check", "the database", "file storage",
per the plugin README's **House style** section. Read the failure yourself
with `get_ci_status`, which names each failed job's failed step and the last
lines of its log, fenced as untrusted data (or with `gh run view <run-id>
--log-failed` when the user has `gh` signed in), but keep that output to
yourself. To
the user, one plain sentence: "The security check found an out-of-date
dependency; I'm updating it and re-shipping." Fix the **root cause**, push,
and cut the next patch tag (a tag is immutable: never force-move one).
The exception: before any fix that moves, deletes or replaces the user's
files, or edits anything under `.github/workflows/`, show the user the change
and ask first, whether or not the row below says so.

| Failing job | Likely cause | Fix via |
|---|---|---|
| `config-integrity` | the repo carries a platform-owned or forbidden path, or `CLAUDE.md` lacks a required header. The failure message names each path; the full list, with the reason for each, is `inno-platform-conventions`' **Files you must not touch** section | **stop and ask; this is not a quiet fix.** Files under `src/` and a root `package.json` can be the user's own code: show the user every flagged path first. Only with their okay, move author code and manifests under `app/` (for example `app/src/`), update the Dockerfile `COPY` paths and the code's imports to match, and delete only what they confirm is not theirs (such as `src/node_modules/`, or a `src/gateway/` an older platform's build left). Never move or delete author code unprompted before a tagged deploy. See `inno-platform-conventions` |
| `secrets` (the `Secret scan (gitleaks)` error) | gitleaks found a credential committed somewhere in the repository's history. It reads every commit on every branch and tag, on every run, a release tag's included, with gitleaks' default rules and the paths they skip (the contract's R8), so an app whose history already holds a secret those rules find fails each push and its next release until it does one of the fixes here. The step log names each finding's commit, file and rule (the secret redacted) and prints its fingerprint | first **rotate** the secret, since it is exposed whatever happens next, and put the new value in an app Variable (`set_app_variables`), never back in the repo. Then, with the user's okay, either **rewrite the history** to remove it from every branch and tag that holds it, or **record the finding's fingerprint**, as the step log prints it, in a `.gitleaksignore` at the repository root: `<commit>:<file>:<rule>:<line>` waives it in that commit alone, and `<file>:<rule>:<line>` in every commit. A fingerprint stops matching when what it names changes: a rebase or any other history rewrite gives the commit a new id, and a move gives the file a new path, so the finding comes back and has to be recorded again (or, better, removed from the history). **Never** delete the file in a new commit as the fix: the old commit still holds the secret, and the gate stays red. The fingerprint is the only waiver (a committed `.gitleaks.toml` or an inline `gitleaks:allow` comment does nothing); the contract's R8 has the full rule |
| `sast` | a semgrep OWASP finding anywhere the gate scans, which is the whole repository and not just `app/` (the scope is `inno-platform-conventions`' **Rendering** section; the log names the file). A `secrets: inherit` line in `.github/workflows/deploy.yml` (older template copies carry one) is a blocking finding too | `inno-platform-conventions` (escaping, SQL); for `secrets: inherit`, tell the user and, with their okay, delete the line (the platform workflow needs no caller secrets) |
| `deps` | a CVE in `app/requirements.txt` or a production npm dependency (what the audit covers is the contract's R8) | bump the pinned dep |
| `dep-age` | a pinned dep is **too new** for the platform's release-age cooldown (`safety.min_release_age_days`; `get_config app=<name>` gives the value in force and its meaning), or `app/package.json` ships with no committed, parseable `app/package-lock.json` so there is nothing to date | **not** a version bump: bumping to the newest release makes it worse. Wait out the cooldown, pin an older vetted version, commit `app/package-lock.json`, or ask a platform admin for an app-scope `safety.min_release_age_days: 0` |
| `container` | Trivy CVE, a `USER` the non-root gate refuses (the forms it accepts are the contract's R1; `inno-containerize` item 2 applies them), missing `EXPOSE 8080`, or the image never answered `GET /healthz`; a failure titled `Trivy` (`trivy exited <n> without a verdict`) is the scanner's, not a finding; one titled `Docker build` is the image build | `inno-containerize`; for `Trivy`, re-run the workflow, and if it repeats ask a platform admin; for `Docker build`, fix the Dockerfile or the files it copies |
| `container` fails with `Accessibility check failed` (only when the app's `safety.a11y.mode` is `enforce`) | the accessibility report found something that blocks in `enforce` mode: an unwaived critical or serious violation, or a landing page `/` (or every page) the app left unscannable. Exactly what blocks, and what only warns, is the `enforce` row of the mode table `get_app_accessibility` serves | read what the report marks as blocking (`inno-safety-preflight` §1c) and fix it, push, confirm the gates are green, then cut the next patch tag. A failing `/` has to render in CI, where there is no stored data, as a real page (an empty state, not an error or a redirect off the app): `app/inno-a11y.json` adds pages that render without stored data, but it never stands in for `/`. A rule that is wrong for this app: name its rule id and have the user ask a platform admin for a time-limited waiver, `safety.ignore.a11y.<rule-id>` with an expiry date as its value |
| `scaffold-check` fails with `Nothing deployed` (a release tag's run only) | `app/.needs-build`, the untouched scaffold's marker, is still in the repository, so the tag deploys nothing. On a push it is not a failure: the job skips `deploy` quietly while the marker exists (see §0) | build the app and delete the marker once `app/` holds real code (§0), push, confirm the gates are green, then cut the next patch tag |
| `deploy` fails with `app_stopped`, or a container app's `container` job fails at `SBOM upload failed` naming it | the app was stopped by the lifecycle (or deliberately), and **stopped apps cannot be deployed**. Only a release tag's run fails this way (a container app's at its `container` job's SBOM upload, before `deploy` runs); a push to the default branch still runs every gate green on a stopped app, so a clean preflight is not evidence that the app can deploy | `inno-manage-app`: `start_app` first, then cut the next patch tag |
| `app-build` fails with `Missing app/package-lock.json` (function-shaped apps) | `app/package.json` exists but no lockfile is committed (the contract's §1.1 **Dependencies** bullet). This job runs on pushes too, so the failure blocks before any tag exists | run `npm install` inside `app/`, commit `app/package-lock.json`, push, confirm `app-build` is green, then tag |
| `app-build` fails in `npm ci` (titled `Dependency install`), or its `Bundle the app Worker` step reports `Could not resolve "<package>"` with the titled error `Undeclared import`, or reports it with the titled error `devDependency imported at runtime` (function-shaped apps; on pushes as well as tags) | the lockfile no longer matches `app/package.json`, or the code imports a package not declared anywhere (nothing is installed at the repo root), or the code imports at runtime a package declared only under `devDependencies` (`app-build` installs `--omit=dev`, so that tree was never installed) | for an undeclared package: declare it in `app/package.json`, run `npm install` inside `app/`, commit both files, push, confirm `app-build` is green, then cut the next patch tag. For a devDependency: move it as **Moving a devDependency into dependencies**, below this table, says; then commit `app/package.json` and `app/package-lock.json`, push, confirm `app-build` is green, then cut the next patch tag |
| `app-build` fails with `Symlink escapes the repository` or `Dangling symlink` (function-shaped apps; the step ends `A symlink in your repository points outside it; a link may name only a file inside your repository. Remove it, or point it inside.`) | a link in the checkout points outside the repository or nowhere. The check walks the whole checkout but `.git` and the platform's own CI checkout, `node_modules` directories included, which `config-integrity` does not walk: a link an installed package ships, a `file:` dependency that points outside the repository, a link among a `file:` dependency's own dependencies (installed in a `node_modules` beside it), or one in a `node_modules` committed anywhere but the repository root and `app/` (those two are removed before the install). A committed link anywhere else fails `config-integrity` first. A link may name only a file inside the repository | for a `file:` dependency, bring what it points at inside the repository; for a package that ships such a link, pin a version that ships none, or replace the package; for a committed `node_modules`, remove it from the repository; each with the user's okay. Push, confirm `app-build` is green, then cut the next patch tag |
| `app-build` fails with `deploy-bundle failed: the app Worker's bundle is <N> bytes; the platform takes at most 16777216 (16 MiB) before compression` (function-shaped apps) | the built Worker is over the platform's size cap (the contract's §1.1) | drop large imported files, or dependencies the Worker does not use, and keep large data in the app's file storage; push, confirm `app-build` is green, then cut the next patch tag |
| `deploy` fails at finalize with `script_rejected` (function-shaped apps; the `Finalize deployment` step logs `deploy-complete failed (409): script_rejected: Cloudflare refused the Worker upload (HTTP <status>): <reason>`, the reason Cloudflare's own codes and messages, read whole from up to 2000 characters of its answer) | Cloudflare refused the Worker upload, most often for an error the app's code throws as it starts (at module top level, outside `fetch`), or for a Worker over Cloudflare's own size limit after compression. A 400 can also be the platform's side: a binding whose database or file storage was deleted outside the platform, which the reason names. Nothing went live, and the app keeps serving its previous version | read the reason on that line. If it is about the app's code, fix the code, push, confirm the gates are green, then cut the next patch tag. If it names a database or file storage binding, change nothing in the app: tell the user in one plain sentence that the platform could not finish this deploy and that their platform admin needs to look at it, then offer a support bundle. If it is about neither, re-run the whole tag run once (`gh run rerun <run-id>`); if it repeats, stop and offer a support bundle |
| `deploy` fails with `app_not_deployable` | the app was stopped, or its repo lost the platform GitHub App, while this deploy was starting | if the repo was unlinked, have the user reinstall the GitHub App on it first (re-linking leaves the app stopped); then `start_app` (`inno-manage-app`) and cut the next patch tag |
| `deploy` fails at finalize with `app_not_deploying` | the app was stopped or purged while the deploy ran; nothing went live. (A newer deploy of the app started meanwhile answers `deployment_not_completable` instead, which `references/deploy-failures.md` covers: never re-run the older release on its own) | `app_status` to see which; if stopped, `start_app`, then cut the next patch tag |

The rarer `deploy` and broker failures and warnings, each with its fix, are
in `references/deploy-failures.md`. Read it when the run shows any of
these: a tag run's `container` job failing at `SBOM upload failed`;
`No scanned image recorded`; `Image mismatch` or `image_mismatch`;
a `deploy-token failed` line naming `app_not_ready`, `image_not_recorded`,
`link_invalid`, `link_source_missing` or `app_busy`, or, for a container
app, naming `upstream_error` or `diagnostics_unavailable`;
a `deploy-complete failed` line naming `deployment_not_completable`,
`link_invalid`, `link_source_missing`, `app_busy`, `host_in_use` or
`host_check_failed`;
a container app's `deploy-complete failed` line naming
`image_not_this_apps`, `container_rollout_failed`,
`container_policy_unexpected`, `container_namespace_missing` or
`platform_key_missing` (change nothing in the app before reading its row);
a function app's `App Worker bundle` error from the `Check the downloaded
bundle against app-build's digest` step or the `Hand the bundle to the
platform` step, or its `deploy-complete failed` line naming
`bundle_missing`, `bundle_mismatch`, `bundle_invalid`,
`bundle_compat_mismatch` or `bundle_store_unavailable`;
a `deploy-complete failed (500)` line, or `deploy-complete failed: no answer
within 540 s`;
`policy` failing with `Platform refused this app` (on a push or a tag: the
line names `app_mismatch`, with the app this repository is registered as
and the line to fix, or `repo_unlinked`) or with `Invalid app name`, or
warning `Gate policy unavailable`;
a tag run's `deploy-sbom failed (403)` or `deploy-token failed (403)` line
naming `repo_unlinked` (an unlink after the `policy` job passed); or the
deploy job's last step ending in an `App not released` warning.

**A failed release releases the app at once.** When the `deploy` job fails
after the platform started the deployment (a finalize refusal, a failed
image push or bundle hand-over, any failure after the token), its last
step, `Release the app after a failed deploy`, asks the platform to undo
that start and ends in one line. `App released` (a notice): the platform
set the app back to active, or to created if it never completed a deploy,
so `stop_app`, `set_app_variables` and the rest work at once; fix what
failed above it, then cut the next patch tag. It says nothing about which
code serves: most failures leave the previous release serving, but a
function app's finalize that failed after its upload landed already serves
the new code (the `deploy-complete failed (500)` row and the message-less
`deployment_not_completable` case in `references/deploy-failures.md`), and
a container rollout that timed out may still finish (its
`container_rollout_failed` row).
`Nothing to release` (a notice): the deployment was no longer this run's
deploy in flight, most often because a finalize completed first, as its
sentence says; read `app_status` before anything else. `App not released`
(a warning): `references/deploy-failures.md` has its row. A run that was
cancelled or timed out never reaches that step: `inno-manage-app`'s **A
deploy whose CI run died** says what holds the app then.

A gate failure is real signal: nothing in the repo or the run overrides it.
A platform admin can turn a gate off for an app by policy (`safety.gate.*`,
which `get_config app=<name>` shows; the run then logs `SAFETY GATE
DISABLED`), but that is a policy decision about the app, never the fix for
a finding. A finding that's a false positive gets a **central admin
ignore** (see `inno-safety-preflight`), never an in-code workaround.
Gitleaks is the one exception: it has no central ignore family, so a
false-positive `secrets` finding is waived by its fingerprint in a
`.gitleaksignore` in the app's own repo, as the `secrets` row above says.

#### Moving a devDependency into dependencies

When `app-build` reports `devDependency imported at runtime` for a package,
that package's entry moves from `devDependencies` to `dependencies` exactly
as it stands, specifier and locked version unchanged. The error's own
`Move it:` line carries the command, with the package already named. Read
`references/devdependency-move.md` before you run it: it has the same
command for a move by hand, what it changes in `app/package.json` and
`app/package-lock.json` and how to check that, and the look-alike command
that ships a version the author never chose.

### When you're stuck: offer to build a support bundle

If the same gate still fails after **two** genuine root-cause fix attempts,
stop retrying. Summarize plainly, then **ask permission** to create a
diagnostics **support bundle** via the **`create_support_bundle`** MCP tool
(`app`, plus a plain-language `description`). Give the user the download
link it returns and relay the answer's next step: send the zip to a
platform admin (the status's `Support:` line names where, when the platform
sets one). The caps and refusals are `inno-manage-app`'s support-bundle
section; the one to expect here is `bundle_limit_reached`, and the answer
to it is to send the most recent existing bundle rather than retrying.

## 4. On success: provenance, then the live URL

The `deploy` job (tag runs only) presents a GitHub OIDC token to the
platform's deploy broker, which answers only the pinned reusable workflow,
the `CI workflow:` line of the status you read in the Version gate (keep
`deploy.yml`'s `uses:` reference exactly as `register_app` returned it),
running for a `refs/tags/v*` release tag. A push to any branch, a fork, or a
`deploy.yml` edited to skip gates gets `403 deploy_denied`: there is no code
path where removing the gates yields a working deploy. The release tag is
recorded on the deployment, and the safety sweep's auto-respin rebuilds at
exactly that tag. A container app's deploy ships exactly the image the
`container` job scanned, pushed with a token scoped to that push. A
function app's run holds no deploy credential at all: the deploy job checks
the bundle `app-build` built against that job's digest before it requests
any token, hands it to the platform, and the platform uploads the app's
Worker itself, setting every binding. The served account
is `get_platform_docs`' **Releases** and **CI gates** sections and the
contract's R7 and R9.

On success, report:

```
Shipped v<X.Y.Z>: <the app URL, as reported by app_status / register_app>
```

and say who can reach it and what it is told, from the `Audience:` and
`Identity:` lines of `app_status`:

- **members-only** (where every app starts): only the owner plus anyone
  granted access via `inno-manage-app`'s `grant_access` can reach it. On a
  browser app the platform signs each person in on their first visit (what
  they see is `get_platform_docs`' **Signing in and out: what people see**),
  and anyone else who signs in sees a plain "No access" page.
- **internal**: everyone who signs in can reach it, members or not.
- **public**: anyone on the internet can reach it, with no sign-in.

Then the identity: an identity-aware app is told who each caller is, and an
anonymous app never is, at any audience.

**When the design meant the app for internal or public** (`inno-new-app`
§1b, `inno-migrate-app`'s item 9) and it is still members-only, the release
did not widen it, and you do not widen it here. Hand the owner to
`inno-manage-app`'s widening review for `set_app_access`: the review of what
the wider audience reaches, one precheck call, and the owner's guardrails
acceptance. Public needs an anonymous app; for an identity-aware app the
review names the two-app pattern instead.

For a `container` app, add one plain line with the tag run's accessibility
report counts: critical, serious, moderate and minor findings, and how many
pages could not be checked (`inno-safety-preflight` §1c says where to read
them). In `report` mode say that they did not block this release, and that
they are what a tool detected, not a verdict that the app is accessible. If
the report did not run, or `safety.a11y.mode` is `off`, say that instead of
quoting zeros.

For an **mcp-function** or **mcp-container** app, report the **MCP endpoint** (`…/mcp`, as returned by
`app_status` / `register_app`) instead of a browser URL, and give the user
the steps for the client they use, with the endpoint filled in:

- **Claude Desktop or claude.ai:** open **Settings**, then **Connectors**,
  and choose **Add custom connector**. Give it the app's name and paste the
  endpoint as its URL, then **Add**, then **Connect**. In a chat, turn the
  connector on from the tools menu under the message box before asking for
  it.
- **Claude Code:** run `claude mcp add --transport http <app name> <endpoint>`,
  then restart the session (or run `/mcp` and authenticate it, then restart:
  a client lists a server's tools when its session starts).

On a members-only or internal app the first connection opens a browser
window: the platform's sign-in, then a consent page naming the app. Tell the
user to click **Approve** once and wait: a second click on the same page
shows "Consent page not valid" even though the first one worked, and the
connector is then connected all the same. A public MCP app asks for no
sign-in. Who may connect follows the app's audience, as above.

**On a brand-new app's first-ever deploy, say what the user may see at
first when you hand over the URL or endpoint; don't just paste a bare
link.** From platform v0.17.9 a registered app's address answers before its
first deploy, with a page saying the app has not been deployed yet, and the
first deploy switches it to the app within seconds. Say something like: "if
it shows a page saying the app has not been deployed yet, or doesn't load
on the first try, wait a minute and reload rather than refreshing or
re-clicking repeatedly." A first lookup of the address that lands in the
seconds of the switch can get it cached as missing on the user's own
machine for minutes, even after the app is live (below); a browser that
already showed the not-deployed page keeps its answer through the switch.
On a platform before v0.17.9 the
address has no record at all until the first deploy and can take up to
roughly a minute to resolve; the same words fit. This caveat doesn't apply
to redeploys of an already-live app: its address already serves the app.

Container-shape redeploys (`container`, `mcp-container`): a deploy starts a
new container instance on the next request, so a fix takes effect with no
`restart_app`; the instance from before keeps its old version and values
only until it stops: from the new host's first request on, or within about
six minutes of the deploy whatever the traffic (contract §2.3).

### Do not curl, dig, or otherwise resolve the hostname to "verify" success

Never look up the app's hostname (the `App host pattern:` line of the status
you read in the Version gate, with the app's name in place of `{app}`;
`register_app` reports the real one) yourself, via `curl`, `dig`,
`nslookup`, a browser navigation or the like, as a way to confirm the deploy
worked, above all right after a brand-new app's first deploy. From
platform v0.17.9 the hostname has a DNS record from registration on (the
platform's placeholder, which serves the not-deployed page), but the first
deploy switches it to the app: the platform removes the placeholder record,
then attaches the app's own domain, and for the seconds between the two the
hostname has no record. (On an older platform it has none until the first
deploy, and the new record can take up to roughly a minute to propagate.)
Any command you run executes on the user's own machine, sharing their real
network stack, not an isolated sandbox. A lookup that lands in that window
gets a negative (NXDOMAIN or SERVFAIL) answer, which
can be cached independently in several places (the user's router-level DNS
resolver, such as AdGuard Home or Pi-hole, and their OS's local resolver
cache, such as macOS `mDNSResponder`) for minutes. The app then looks broken
to the user long after it went live, and it won't self-correct until each
cache's negative TTL expires or someone flushes it by hand.

The `deploy` job's success or failure and the `app_status` MCP tool's
deployment timestamp are the authoritative, side-effect-free signals: use
those. If the user wants to see the app for themselves, let them visit it
in their own browser; don't pre-check it for them.

### Right after a deploy, health may read `re-probe pending`, which is not a verdict

Right after a deploy, `app_status` can read `Health: re-probe pending (not
answering yet: <what the probe saw>, checked again within the hour)`,
followed by `; last recorded: <status>` when an earlier probe recorded one.
The probe a deploy fires never judges a failure: it defers every unhealthy
result to an hourly pass and notifies no one, while a healthy answer is
recorded at once. All of this holds only when probes run for the app
(`health.probe_enabled`, which `get_config app=<name>` shows): with them
off, no probe follows a deploy or a restart, no pending line appears, and
`app_status` keeps the last verdict. The rule and its clocks are the
contract's R2 (`get_app_contract` with `sections: ["R2"]`), and
`inno-containerize` item 4 is the plugin's home for them. What that means for you:

- The last-recorded status is from before this deploy and says nothing
  about it. On a brand-new app a pending line is normal while a container
  finishes cold-starting, and one failing answer right after any deploy can
  be transient.
- A broken deploy alarms only when an hourly pass judges it, within about
  70 minutes, never at once: do not tell the user a broken deploy would
  already have alarmed, and do not read a pending line, or an old
  `healthy`, as proof the new deploy works.
- `restart_app` re-checks health too, for a running app (active or warned),
  as `start_app` does after a start: health reads pending, then a healthy
  answer within about a minute, while a failing one is left to the next
  hourly pass to judge, as a deploy's is. It does not update the deployment
  record, so it never restarts the 10 minutes in which an hourly pass
  defers after a deploy.
- Re-running the whole tag run (`gh run rerun <run-id>`, without `--job`: a
  container deploy needs the image that same run's `container` job scanned,
  kept for only one day) finalizes another deploy, whose probe records a
  healthy answer at once but defers a failing one again and restarts the 10
  minutes in which an hourly pass defers. A re-run can confirm a fix sooner
  than the next hourly pass, but it never surfaces a failure sooner, and it
  can delay the alarm.
