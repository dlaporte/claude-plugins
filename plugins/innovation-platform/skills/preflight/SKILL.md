---
name: preflight
description: Use before pushing to main on an inno-{app} repo — runs the same security/quality gates locally that CI enforces, for fast feedback. Explains what each gate checks and what a failure means.
---

# preflight

CI is authoritative — a green local run doesn't skip CI and a red local run
doesn't mean CI would necessarily fail identically (versions can drift). But
these four commands mirror the platform's `sast`, `secrets`, and `deps` CI
jobs closely enough that running them locally first saves a push-wait-fail
loop. Run all four from the repo root before handing off to `ship`.

## 1. Semgrep — OWASP Top Ten, scoped to `app/`

```bash
semgrep --config p/owasp-top-ten --error app/
```

This is the exact command the `sast` CI job runs (scoped to `app/` only —
the gateway under `src/` is hash-pinned by `config-integrity` and the caller
workflow is inert, so scanning them would only flag the platform's own
intentional patterns). `--error` makes semgrep exit non-zero on any finding,
which is what makes this a gate rather than a lint suggestion. A failure here
usually means: unescaped HTML interpolation (see `platform-conventions`),
raw SQL string-formatting instead of parameterized queries, or a subprocess/
`eval`-shaped injection sink. Fix the flagged code, don't suppress the
finding, unless you're certain it's a false positive — and if so, use a
scoped `# nosemgrep: <rule-id>` with a comment explaining why, not a blanket
disable.

## 2. gitleaks — secret detection

```bash
gitleaks detect --no-banner
```

Scans the full git history (not just the working tree) for committed
credentials, API keys, and tokens. This is what the `secrets` CI job runs via
`gitleaks-action`, which fails the job on any finding — there's no
`continue-on-error` on that step by design. If it flags something: rotate
the credential immediately (a git-history rewrite alone doesn't un-leak an
already-committed secret), then remove it from history before re-pushing.
Never disable this gate to "get past" a finding.

## 3. pip-audit — Python dependency CVEs

```bash
pip-audit -r app/requirements.txt
```

Matches the `deps` CI job's `pip-audit -r app/requirements.txt` step exactly.
A failure means a pinned version in `app/requirements.txt` has a known CVE —
bump the pin (respecting the `starlette>=1.3.1,<2` constraint from
`platform-conventions`) rather than pinning around the scanner.

## 4. npm audit — JS dependency CVEs, prod deps only

```bash
npm audit --omit=dev
```

The CI `deps` job runs `npm audit --omit=dev --audit-level=high` (only runs
at all `if [ -f package.json ]`). `--omit=dev` matters: the deployed Worker
bundles only runtime dependencies (`@cloudflare/containers`, `hono`, `jose`)
— `wrangler`/`vitest`/`esbuild` and other dev tooling are never shipped, so
their advisories don't affect the deployed artifact. Since `package.json` and
its lockfile are template-owned and pinned by `config-integrity`, a finding
here is a platform-level issue to flag upstream, not something you should
try to fix by editing `package.json` yourself (that edit would itself fail
`config-integrity`).

## Running all four together

```bash
set -e
echo "== semgrep ==" && semgrep --config p/owasp-top-ten --error app/
echo "== gitleaks ==" && gitleaks detect --no-banner
echo "== pip-audit ==" && pip-audit -r app/requirements.txt
echo "== npm audit ==" && npm audit --omit=dev
echo "ALL GREEN — safe to ship"
```

If any command isn't installed locally, install it before skipping it
(`brew install semgrep gitleaks`, `pipx install pip-audit`) — these are
lightweight, fast tools designed to run pre-push, and skipping one just moves
the failure to CI where the feedback loop is slower.
