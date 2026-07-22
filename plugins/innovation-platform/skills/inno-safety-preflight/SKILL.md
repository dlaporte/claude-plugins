---
name: inno-safety-preflight
description: Use when the user wants their inno-{app} checked before shipping ("run the safety preflight", "is this safe to ship?", "check my app"). Pushes to main — which runs the platform's REAL safety gates and deploys nothing — then narrates the results with realtime guidance, plus a guardrails policy review. A failure or guardrails violation is a hard stop before inno-ship.
---

# inno-safety-preflight

Deploys are release-driven on this platform: **a push to main runs every
safety gate and deploys nothing**. That run — on the platform's own runners,
with the exact pinned tool versions and the admin-configured gate policy — IS
the preflight. Never install or run scanners locally: local results drift
from CI's and know nothing about centrally-configured ignores or gate
toggles.

Three things are checked here, and **all are hard requirements before
`inno-ship`**:

1. The **safety gates** (CI): config-integrity, secrets, SAST, dependency
   audit, container build + image CVEs.
2. The **guardrails policy** (you): a qualitative read of the app against
   the platform's acceptable-use policy.
3. The **application contract** (you): the app's conformance to the
   platform's runtime requirements that CI can't see.

## 1. Guardrails + contract review (do this while CI runs, or first)

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
MUSTs — focusing on what CI does NOT enforce mechanically: identity read
only from the gateway headers with no home-grown auth (R3), a sign-out link
targeting the team-domain logout (R4), durable state in the platform stores
rather than local disk or memory (R5/R6), `/healthz` present and cheap (R2),
and no reliance on unsupported patterns (background work, machine-to-machine
callers, connections that must survive sleep). A contract violation is the
same hard stop as a guardrails one: name the requirement, fix or guide the
fix, re-check.

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
| config-integrity failure | Either a platform-pinned file was modified (package.json, wrangler resource blocks, template CLAUDE.md headers — revert it, never editable app-side) or the repo contains `src/gateway/` (the platform injects the gateway at build time — delete the directory). |
| container failure | Dockerfile contract problem — hand off to `inno-containerize`. |

Diagnose privately (`get_ci_status` annotations or `gh run view --log-failed`);
don't paste raw logs at the user. After two failed fix attempts on the same
gate, ask permission to file a `report_issue` for the platform team.

## Done

End with a clear verdict: **"Safe to ship"** (gates green + guardrails clean
→ point at `/inno-ship`) or **"Not yet"** with the specific blockers listed.
