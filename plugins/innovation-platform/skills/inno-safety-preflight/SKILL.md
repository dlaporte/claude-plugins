---
name: inno-safety-preflight
description: Use when the user wants their app checked before shipping ("run the safety preflight", "is this safe to ship?", "check my app"). Pushes to the default branch, which runs the platform's REAL safety gates and deploys nothing, then narrates the results with realtime guidance, plus a guardrails policy review. A failure or guardrails violation is a hard stop before inno-ship.
---

# inno-safety-preflight

## Version gate — do this first

Before anything else in this skill, do these five steps in order.

1. If no `inno-platform` tools are available at all, the platform address is
   probably unset. Tell the user to open their platform's panel, copy the
   configure command from its Connect Claude Code card, run it in a terminal,
   and restart Claude Code. Then STOP.
2. Read the `version` field of `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`
   and call the `get_platform_status` MCP tool with it as `plugin_version`.
3. If the `Plugin:` line says `OUTDATED`, `version not reported`, or
   `reported version is not a MAJOR.MINOR.PATCH triple`, STOP. Tell the user
   to run the commands that line gives, then restart Claude Code and start
   again. Do not continue on a stale plugin: its guidance may describe
   platform behavior that no longer exists. If there is no `Plugin:` line at
   all, the platform sets no minimum version: go on to the next step.
4. If the `Plugin:` line says `current` and adds that a newer version
   `is available`, that is advice, not a block. Mention it once, with the
   commands from the `Update commands:` line, and go on to the next step.
5. If the status has no `Template repo:` line, the platform is older than
   v0.15.8. Say so, ask the user's admin to upgrade it, and STOP before any
   step that needs an instance value. Never fall back to a literal value.

Carry on.

Deploys are release-driven on this platform: **a push to the default branch
runs every safety gate and deploys nothing**. That run, on the platform's
own runners, with the exact pinned tool versions and the admin-configured
gate policy, IS the preflight. Never install or run scanners locally: local
results drift from CI's and know nothing about centrally-configured ignores
or gate toggles.

**Know the policy that applies to THIS app before you narrate anything.** Call
`get_config app=<name>` — the app's owner can read it, no admin needed. It
gives you the actual `safety.gate.*` toggles, the `safety.a11y.mode` in force
(`report`, `enforce` or `off`), the `safety.min_release_age_days` cooldown in
force, and any `safety.ignore.<semgrep|trivy|deps|a11y>.<id>` suppression
written at this app's own scope, platform-wide ones being withheld
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

Six things are checked here. **The first five are hard requirements before
`inno-ship`**; the sixth is advisory:

1. The **safety gates** (CI) — eight jobs, all `needs:` prerequisites of
   `deploy`, plus the `policy` job that fetches the admin gate policy:
   `config-integrity`, `secrets` (gitleaks over the full history; its only
   sanctioned suppression is a `.gitleaksignore` committed in the app's own
   repo, because it is the one gate with no central ignore family), `sast`
   (Semgrep over the whole repository, not just `app/`; the scope is
   `inno-platform-conventions`' **Rendering** section), `deps`
   (dependency audit: `npm audit` covers only `app/package.json`'s
   **production** dependencies, `--omit=dev`; since platform v0.14.21, and
   contract version 21 states it, the `app-deps` job installs with
   `--omit=dev` too, so the audited set and the installed set are the same,
   and a runtime import must therefore sit under `dependencies`),
   `dep-age` (the
   dependency-release-age cooldown — see
   the table below), `container` (build + image CVEs + non-root/`EXPOSE 8080`
   + a `GET /healthz` smoke test that requires **exactly 200**, run for
   `container` and `mcp-container`
   apps — the image checks are skipped for the function-shaped `function` and
   `mcp-function` types; Trivy runs at HIGH and CRITICAL with
   `--ignore-unfixed`, over OS and language packages alike, so only findings
   that have a fix available can fail it), and
   `scaffold-check` (suppresses deploy while the `app/.needs-build` template
   marker is still present, which is also the one condition under which a
   leftover `scaffold/` directory is tolerated), and `app-deps` (installs a
   function-shaped app's
   `app/package.json` with `npm ci --ignore-scripts --omit=dev` inside
   `app/`, on every push as well as at the tag; a missing or stale
   `app/package-lock.json` hard-errors here, and the full rule is
   `inno-platform-conventions`' **Node apps** paragraph).
   After its smoke test the `container` job also writes the reports item 6
   reads; only the accessibility report can turn the job red, and only in
   `enforce` mode.
2. The **guardrails policy** (you): a qualitative read of the app against
   the platform's acceptable-use policy.
3. The **application contract** (you): the app's conformance to the
   platform's runtime requirements that CI can't see.
4. The **app-code security notes** (you): the app-level risk classes the
   perimeter can't close — authorization/IDOR above all.
5. **Declared variables** (you, repo-local): if `app/inno-variables.json`
   exists, whether it's well-formed and whether any name it marks
   `required` still has no value.
6. **Accessibility review** (you, plus CI's reports; **advisory**): the app's
   browser pages against `get_app_accessibility`, a keyboard pass, and the
   accessibility, response-header and Dockerfile reports the `container` job
   writes (since platform v0.14.30, contract version 22). In the default
   `report` mode nothing here blocks `inno-ship`. When an admin has set the
   app's `safety.a11y.mode` to `enforce`, a blocking accessibility finding
   fails the `container` job, and that red gate is item 1's hard stop. How
   to run it and read the reports is §1c.

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
CI-enforced, by the `container` job's smoke test, and both enforcers require
**exactly 200**, so a 204 or a redirect to `/healthz/` fails. But CI only
sees that it answers inside the image, so still read it for the parts CI
can't: cheap, no side effects, and **independent of storage**. That last one
matters because the runtime probe calls it with a platform credential chosen
by the app's perimeter, not as any real user. A contract violation
is the same hard stop as a guardrails one: name the requirement, fix or
guide the fix, re-check.

Finally, call the `get_app_security` MCP tool and review the app's code
against the sections that apply to it. Its closing **How to use this**
section says which sections a given app may skip, and anything rendered in
a browser keeps some of them, so no browser-facing app skips the review.
CI's scanners catch injection patterns and known-vulnerable deps, but the
highest-impact app bug, **authorization / IDOR**, is invisible to them. For
any app with **per-user data, an admin surface, a state-changing write, or a
call to a paid/external upstream**, verify every query for
user-owned data is scoped by the caller's `X-Forwarded-User` (not by an id
from the request), privileged surfaces gate on a role the app keeps itself
(keyed on `X-Forwarded-User`, never on `X-Forwarded-Groups`, whose rule is
`inno-platform-conventions`' **Identity** section), values bind
in SQL, output is escaped, and expensive actions are bounded per caller. A
real authorization hole is a hard stop: fix or guide the fix before
`inno-ship`. A missing response header (its §9) is a recommendation, not a
stop: offer the fix, and for a `container` app item 6's header report shows
what the app sends today.

## 1b. Declared variables (repo-local, before you push)

If the repo carries `app/inno-variables.json`, validate it the same way
`inno-ship` does (same name grammar, reserved names, 32-entry cap, and the
three allowed fields; see there for the exact rules) and, for every
`required: true` name, check whether it already has a value
(`list_app_variables`, or `app_status`, which names an unset required one
directly). Nothing here is CI-enforced (the file is read only at the tag's
`deploy` finalize step, never at a push), so this is purely advisory, and
it's the only warning an author gets before their first deploy leaves a
required key silently unset.

## 1c. Accessibility review (advisory: start while CI runs, then read its reports)

Who this covers:

- **`container` and `function` apps**: their browser pages. A `container`
  app also gets CI's accessibility and response-header report. A `function`
  app has no container for CI to run, so this review is its only check.
- **`mcp-function` and `mcp-container` apps** have no browser UI: say the
  review does not apply. An `mcp-container` app still gets the Dockerfile
  report, which every container-shaped app gets.
- A `container` app that serves no HTML at all (an API) is not applicable
  either: say so in your summary rather than listing it as a pass.

**While CI runs:**

1. Call `get_app_accessibility` and review the app's pages against it. Fix
   what you find (or guide the fix), and fold it into the next push.
2. Do a keyboard pass of a couple of minutes on a running copy of the app
   (the live one if it is deployed, or a local run): Tab through every
   page and check that everything can be reached and operated, and that you
   can always see where focus is. If you cannot drive a browser yourself, ask
   the user to do it and tell them what to look for.
3. CI always scans `/`. To cover more of a `container` app, list pages that
   render **without stored data** (the CI run has none) in
   `app/inno-a11y.json`; the served notes give its format and limits. The
   file only adds pages, so it never stands in for `/`.

**After CI** (a container-shaped app), read the reports in the GitHub Actions
run. They live only there, never on the platform, and in `report` mode their
step is green, so neither `get_ci_status`'s job conclusions nor `gh run view
--log-failed` shows them:

- Open the run link `get_ci_status` returns: the run's summary page carries
  in full each report the run wrote (the accessibility counts by impact and
  its per-route table, the response headers, and the Dockerfile findings).
- With `gh`: `gh run view <run-id>` lists the first findings as annotations
  (GitHub shows at most 10 of each kind per step, so the rest are only in
  the summary), and `gh run view <run-id> --log` carries one count line per
  report, beginning `a11y:` and `dockerfile-report:`.

There is no report when the `container` job failed before its smoke test
passed, or when the app's `safety.a11y.mode` is `off` (the run warns
`Accessibility check off` instead). `Accessibility scan did not run` means
no page was scanned, which is never a clean result; read the reason it
gives. A reason on the platform's side (one marked platform-side, or a
`/healthz`, download or scanner failure) never blocks. A reason that is the
app's (a 4xx, a redirect off the app, a blank page, a page that never
finished loading) is the app's to fix, and it blocks only in `enforce` mode,
where the job also fails with `Accessibility check failed`.

Translate them for the user, in plain terms (the plugin README's **House
style** section):

- **Accessibility findings:** fix critical and serious ones first; each
  names its rule and links an explanation of the fix.
- **Not scanned:** a page listed as not scanned was not checked, which is
  never the same as clean. A 5xx there usually means the page needs stored
  data, which CI does not have; it never blocks.
- **Response headers and Dockerfile findings** never block (the header
  report runs inside the accessibility scan, so it is absent when the mode is
  `off`): explain each in one sentence and offer the fix (`get_app_security` §9 for
  the headers, `inno-containerize` for the Dockerfile).
- **In `enforce` mode** a blocking finding fails the `container` job with
  `Accessibility check failed`; §3's table has the row.

Say plainly what a tool checked, what you checked by hand, and what was not
checked. Never call the app "accessible" or "WCAG compliant" because the
report is clean: a tool finds only part of the problems, as the served notes
explain. A rule that is wrong for this app is waived by a platform admin
(`safety.ignore.a11y.<rule-id>`, the value an expiry date), never worked
around in the page.

## 2. Push and watch the gates

Before pushing, look at `.github/workflows/deploy.yml`. If it has a
`secrets: inherit` line (repos made from older copies of the template do), the
`sast` gate will fail on it: tell the user, and with their okay delete that
line as part of this push. Nothing else in the file changes.

**Confirm the branch before pushing.** The `deploy.yml` `register_app` handed
back triggers gates only on pushes to the repository's default branch (a `v*`
tag deploys from any branch). Compare `git branch --show-current` against
`gh repo view --json defaultBranchRef --jq .defaultBranchRef.name`; if they
differ, do not push blind, tell the user the gates only run on the default
branch, and ask whether to switch to it or merge there first.

This branch check, the symlink check below, and the reading of
`get_ci_status` after it are the plugin's one copy; `inno-ship` and
`inno-migrate-app` point here for them.

```bash
git add -A

# Committed DIRECTORY symlinks fail config-integrity (check 1c) and there is
# no policy toggle for it. Run this AFTER `git add -A`, so the index covers
# both already-tracked links and ones you are about to commit, and so
# gitignored app/node_modules (which npm fills with directory links) drops
# out on its own. A link to a FILE is legal, so classify rather than reject
# on mode alone: -d and -e follow the link, which is the test the gate makes.
git ls-files -s | awk '$1 == "120000"' | cut -f2 | while IFS= read -r l; do
  if   [ -d "$l" ];   then echo "BLOCKED (directory link): $l -> $(readlink "$l")"
  elif [ ! -e "$l" ]; then echo "BLOCKED (dangling link):  $l -> $(readlink "$l")"
  fi
done

git commit -m "<why-focused message>"   # if uncommitted work
git push origin HEAD
```

Nothing deploys from this push. Watch the run either way:

- **MCP (no gh needed):** call `get_ci_status` with the app name — it returns
  the run status, the run link, and each gate's conclusion. Its first line
  also names the branch and commit the run is for ("... on «<branch>»,
  commit `<sha>`"), with the branch fenced in «» guillemets because anyone
  who can push to the repo chooses it; with no `run_id` it
  returns only the latest `deploy.yml` run, so check that commit (or branch)
  against `git rev-parse --short HEAD` before narrating a green or red
  result as the answer for this push, not a stale one. It also tries for
  file:line failure annotations, but those need the platform GitHub App to
  hold `Checks:Read`, which the App's documented permission set deliberately
  omits, so for a registered app the tool reports the findings as
  unavailable and a failed job's line points at the run link instead.
  Narrate from the job conclusions and that link (or `gh run view
  --log-failed`) when that happens. Two refusals are worth recognizing:
  `app_not_installed` (the App is no longer installed on the repo; the user
  reinstalls it on GitHub) and `repo_not_linked` (registration never
  finished).
  Poll every ~30s while `in_progress`; narrate transitions ("secrets ✓,
  container still building…"). Polling that slowly is well inside the
  platform's call budget, but never poll the same run from several subagents
  at once: the budget is per person, not per agent. The rule is
  `inno-manage-app`'s **Call budget** section.
- **gh CLI (if authenticated):** `gh run watch` from the repo.

## 3. Translate the results — this is the actual product

For each gate, tell the user what happened in THEIR terms. Plain terms, no
provider or product names unless they have shown technical fluency; the full
rule is the plugin README's **House style** section.

| Outcome | What you say / do |
|---|---|
| All green | "All safety gates passed — `/inno-ship` when you're ready to release." |
| **Real finding** (SAST/deps/CVE) | Show the file:line if the annotations came through. If they didn't, open the run link yourself (or run `gh run view --log-failed` when the user has `gh` authenticated) and read the failing step. Explain the risk in one sentence, fix it (or guide the fix), re-push. |
| **Likely false positive** | Never work around it in code (renames, string-splitting, suppression comments). Name the exact finding ID and tell the user a platform admin can add a central ignore for it (`safety.ignore.<tool>.<id>`, where the value is the expiry date, or empty for none), which clears it at both the gate and the periodic safety sweep (an `a11y` ignore clears only the deploy check, because accessibility findings never reach the sweep). A `secrets` finding is the exception: gitleaks has no central ignore family, because its fingerprints are commit-bound and rebase-fragile. Its supported suppression surface is a `.gitleaksignore` committed in the app's own repo, and an entry there is sanctioned, not an in-code workaround. Semgrep has no repo-side escape at all: from platform v0.14.4 (contract version 13) the `sast` gate ignores `# nosemgrep` comments and deletes every `.semgrepignore` before it scans, so neither hides a finding. A semgrep finding is either fixed in the code (when it is real) or ignored centrally by a platform admin (`safety.ignore.semgrep.<rule id>`). |
| `yaml.github-actions.security.secrets-inherit` finding on `.github/workflows/deploy.yml` | A real fix, not a false positive: tell the user and, with their okay, delete the `secrets: inherit` line from `deploy.yml`. The platform's reusable workflow needs no inherited secrets (it uses only the automatic `GITHUB_TOKEN` and OIDC), and repos made from older copies of the template carry that line. Keep the `workflow_dispatch` trigger. |
| `SAFETY GATE DISABLED by platform policy` in the log | Deliberate admin configuration, not a bug. Note it and move on. |
| config-integrity failure | Something in the repo is a file the platform injects at build time, or one it forbids outright; the failure names each path, and the full list with the reason for each is `inno-platform-conventions`' **Files you must not touch** section. Three rules govern how you act on it. **Never move or delete author code unprompted**: files under a root `src/`, and a root `package.json` / `package-lock.json` / `tsconfig.json`, are often the author's real code and manifests in a migrated repo, so show the user every flagged path and, only with their okay, move it under `app/` (for example `app/src/`), updating the Dockerfile `COPY` paths and any imports or build settings that pointed at the old location; delete only what they confirm is not theirs. **Platform-owned files just go**: a root `wrangler.jsonc` or any competing wrangler config, a `.wrangler/` directory, a `scaffold/` that outlived `app/.needs-build`, a root-level `.env*` (its values move into app Variables with `set_app_variable`) and any root package-manager config, plus every `.npmrc` at any depth. **A directory symlink has no policy toggle**: show the user the link, then replace it with the real directory or drop it. If instead `CLAUDE.md`'s required template headers were altered, revert them (the rest of the file is yours). A message that the gate "could not fully inspect the app tree" means a committed directory it could not read; fix or remove that path. Everything else under `app/` (an `app/package.json`, an `app/.yarnrc.yml`, an `app/src/`) is yours and fine. |
| `dep-age` failure | The **inverse** of a CVE finding: do NOT bump to the newest release, that makes it redder. Either a pinned dependency was published more recently than the platform's cooldown allows (`safety.min_release_age_days`, 0 = off and the default, so this only fires once an admin has enabled it; `get_config app=<name>` tells you the value actually in force and how many days you're short by), or the app ships `app/package.json` with no committed, parseable `app/package-lock.json` and there are no exact versions to date at all. Remedies: wait out the cooldown, pin an older vetted version, commit `app/package-lock.json`, or ask a platform admin for an app-scope `safety.min_release_age_days: 0`. Separately from this gate, a function-shaped app that ships `app/package.json` with no committed `app/package-lock.json` fails the `app-deps` job outright, whatever the cooldown says (platform v0.14.2). Since v0.14.14 that install runs on every push to the default branch, so it fails in this very run rather than at the tag. |
| `container` fails with `Accessibility check failed` | Only happens when the app's `safety.a11y.mode` is `enforce`. Read the report (§1c) for what it marks as blocking; the causes and the remedies are the row for it in `inno-ship`'s failure table. Fix, then re-push. |
| container failure | Dockerfile contract problem, or the built image never answered `GET /healthz` with exactly 200 inside the smoke test's budgets (about 90 seconds when the port refuses, about 162 seconds when it accepts and hangs; the clocks are `inno-containerize` item 4); hand off to `inno-containerize`. For a non-root failure: the gate accepts only a plain uid 1 to 2147483647 or a portable name on one clean `/etc/passwd` line (see `inno-containerize` item 2). The image this job scans on the tag run is the exact image that ships: the deploy job pushes it by digest and never rebuilds the Dockerfile. |

Diagnose privately (the `get_ci_status` run link and job conclusions, its
annotations when they come through, or `gh run view --log-failed` if the user
has `gh` authenticated); don't paste raw logs at the user. After two failed
fix attempts on the same gate, ask permission to create a
`create_support_bundle` for the app and hand the user the download link to
attach to a support ticket. The caps and refusals are `inno-manage-app`'s
support-bundle section; the one to expect here is `bundle_limit_reached`,
which is not a reason to retry: point the user at a bundle already created,
since they all cover the same recent window.

## Done

End with a clear verdict: **"Safe to ship"** (gates green and guardrails
clean, and, for a `function` or `mcp-function` app that has
`app/package.json`, a committed `app/package-lock.json` in step with it; point
at `/inno-ship`) or **"Not yet"** with the specific blockers listed. This push
proves the lockfile on its own, because `app-deps` runs on every push to the
default branch, so a missing or stale lockfile is a red job in the run you are
narrating, not a surprise at the tag. (The `deps` gate still builds a
throwaway lockfile when none is committed, so its own green never proved
anything here.) One
exception, and it is about what you REPORT rather than about safety:
`app-deps` is `needs: [policy, config-integrity]`, so a red
`config-integrity` skips it. Nothing unsafe follows, because that run skips
`deploy` too and there is no tag to cut, but a skipped `app-deps` proved
nothing. Do not report the lockfile as clear on such a run, and say that it
will be checked for the first time on the re-push, so a lockfile failure
arriving then is not a new regression. Checking the file yourself is
otherwise belt, not the safeguard: it saves a round trip through CI.

Report the accessibility review (§1c) beside the verdict, not inside it:
what a tool checked, what you checked by hand, and what was not checked. In
`report` mode its findings never turn "Safe to ship" into "Not yet"; in
`enforce` mode a blocking one already shows as a red `container` job.
