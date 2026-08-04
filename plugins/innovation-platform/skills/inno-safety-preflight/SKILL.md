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
cooldown in force, and any `safety.ignore.*` suppression with its expiry date
and the note behind it. Read it, don't assume the defaults: a gate an admin
turned off will simply not appear in the run, and a finding you expect to fail
may be suppressed until a date that has since passed. Two things this buys
you — you stop explaining a job that was never going to run, and you can tell
a user "that CVE is ignored until 2026-09-01, after which this deploy stops
passing" while there's still time to act.

Four things are checked here, and **all are hard requirements before
`inno-ship`**:

1. The **safety gates** (CI) — seven jobs, all `needs:` prerequisites of
   `deploy`, plus the `policy` job that fetches the admin gate policy:
   `config-integrity`, `secrets` (gitleaks), `sast` (Semgrep), `deps`
   (dependency audit), `dep-age` (the dependency-release-age cooldown — see
   the table below), `container` (build + image CVEs + non-root/`EXPOSE 8080`
   + a `GET /healthz` smoke test, run for `container` and `mcp-container`
   apps — the image checks are skipped for the function-shaped `function` and
   `mcp-function` types), and `scaffold-check` (suppresses deploy while the
   `app/.needs-build` template marker is still present).
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
targeting the team-domain logout (R4), durable state in the platform stores
rather than local disk or memory (R5/R6),
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
from the request), privileged surfaces gate on an `inno-` group, values bind
in SQL, output is escaped, and expensive actions are bounded per caller. A
real authorization hole is a hard stop — fix or guide the fix before
`inno-ship`. (A stateless single-view tool can skip this.)

## 2. Push and watch the gates

```bash
git add -A && git commit -m "<why-focused message>"   # if uncommitted work
git push origin main
```

Nothing deploys from this push. Watch the run either way:

- **MCP (no gh needed):** call `get_ci_status` with the app name — it returns
  the run status, each gate's conclusion, and file:line failure annotations.
  Poll every ~30s while `in_progress`; narrate transitions ("secrets ✓,
  container still building…").
- **gh CLI (if authenticated):** `gh run watch` from the repo.

## 3. Translate the results — this is the actual product

For each gate, tell the user what happened in THEIR terms:

| Outcome | What you say / do |
|---|---|
| All green | "All safety gates passed — `/inno-ship` when you're ready to release." |
| **Real finding** (SAST/deps/CVE) | Show the file:line from the annotations, explain the risk in one sentence, fix it (or guide the fix), re-push. |
| **Likely false positive** | Never work around it in code (renames, string-splitting, suppression comments). Name the exact finding ID and tell the user a platform admin can add a central ignore for it (optionally with an expiry) — it then clears at both the gate and the periodic safety sweep. |
| `SAFETY GATE DISABLED by platform policy` in the log | Deliberate admin configuration, not a bug. Note it and move on. |
| config-integrity failure | The repo contains a platform-injected file that must not exist — `src/gateway/`, `package.json`, `package-lock.json`, `tsconfig.json`, or `wrangler.jsonc` (delete it; the platform injects all of these at build time) — or `CLAUDE.md`'s required template headers were altered (revert them; the rest of the file is yours) — or a root-level `.env*`/`.npmrc`/`.yarnrc` slipped in (remove it — a `.env`'s values move into app Variables with `set_app_variable`). Root-only: the app's own `app/package.json` etc. are fine. |
| `dep-age` failure | The **inverse** of a CVE finding — do NOT bump to the newest release, that makes it redder. Either a pinned dependency was published more recently than the platform's cooldown allows (`safety.min_release_age_days`, 0 = off and the default, so this only fires once an admin has enabled it — `get_config app=<name>` tells you the value actually in force and how many days you're short by), or the app ships `app/package.json` with no committed, parseable `app/package-lock.json` and there are no exact versions to date at all. Remedies: wait out the cooldown, pin an older vetted version, commit `app/package-lock.json`, or ask a platform admin for an app-scope `safety.min_release_age_days: 0`. |
| container failure | Dockerfile contract problem, or the built image never answered `GET /healthz` within ~90s — hand off to `inno-containerize`. |

Diagnose privately (`get_ci_status` annotations or `gh run view --log-failed`);
don't paste raw logs at the user. After two failed fix attempts on the same
gate, ask permission to create a `create_support_bundle` for the app and hand
the user the download link to attach to a support ticket.

## Done

End with a clear verdict: **"Safe to ship"** (gates green + guardrails clean
→ point at `/inno-ship`) or **"Not yet"** with the specific blockers listed.
