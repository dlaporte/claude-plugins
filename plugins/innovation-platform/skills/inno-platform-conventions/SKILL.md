---
name: inno-platform-conventions
description: "Use when writing or reviewing code inside an app repo's app/ directory: stack policy, storage, identity, and the files CI will reject if touched. Load this before writing any application code for an Innovation Platform app."
---

# inno-platform-conventions

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

Every app runs behind the platform's front door, one platform-owned Worker
that signs people in and decides who reaches each app (contract §1). A
container app runs in a host Worker the platform uploads for it, and a
function app is its own Worker in the platform's app namespace. Nothing of
the front door or the host lives in your repo, and CI polices the rest;
your job is everything under `app/`. These rules are not style
preferences. Most map to a CI gate that fails the deploy; the rest, R3 to
R6 and R10, no gate can see, so the safety preflight's review judges them
(`inno-safety-preflight`), and the contract's §6 enforcement map says which
is which.

**Fetch the contract before writing app code:** call `get_app_contract` with
`sections: ["2", "3", "4"]` (the requirements R1 to R10, the recommendations,
and the stack policy), adding the section for the app's type (`1.1` for
`function`, `1.1` and `1.2` for `mcp-function`, `1.2` and `1.3` for
`mcp-container`)
and `2.1`, `2.2` or `2.3` when the app reads another app's data through a
link, uses a connection or reads platform variables. Where a skill reads one
requirement it asks for it by its id (`sections: ["R3"]`); when the platform
refuses an id with `bad_request` (a platform before v0.17.7), ask for
`["2"]`, which holds every requirement. Every contract or
section answer opens with the
CURRENT digest-pinned recommended base images. The tool is the live source:
never restate contract values from memory or hard-code a base-image digest.
This skill says how to apply the contract while writing code, and names the
part of it that is authoritative for each rule.

## Refusals every tool shares

The refusals the platform's MCP tools share are named once, in the
instructions the platform's MCP server sends when a client connects, rather
than in each tool's description: first those any tool can answer, then
those the tools that change an app or reach its repository share (the
instructions say which tools). Those instructions are the authoritative
text, so read what each means there; this is what to do next when a tool
answers one:

- `account_inactive`: the account can no longer sign in. Relay the message,
  which tells the user to contact a platform admin and names the instance's
  support contact when it sets one; nothing in the call fixes it.
- `rate_limited`: wait a minute. Inside one skill run it usually means
  something is looping, or several subagents are calling at once.
- `forbidden`: the caller lacks the standing the tool's description names.
  Don't retry it and don't work around it locally; the app's owner or a
  platform admin has to act.
- `app_not_found`: no app has that name. Check the name with the user.
- `invalid_email`: the value is not an email address. Ask the user for the
  address again.
- `upstream_error`: a service the platform calls failed, or the call failed
  in a way the platform did not expect. Its message says what was running
  and whether a retry may help: when it asks for one, retry once; when it
  says a retry will not help, don't: relay its sentence, which says whom to
  tell (a platform admin, through the platform's support contact when it
  names one) and what to tell them (the time it happened and what was
  running).
- `app_busy`: another change to the app, or to an app linked to it, is in
  flight. Retry **once** after a moment, never in a loop.
- `app_deploying`: a deploy of the app is in flight. Wait for it to finish,
  then retry: a deploy whose CI run fails releases the app at once, so the
  refusal normally clears as the run ends, green or red. If it does not
  clear, `inno-manage-app`'s **A deploy whose CI run died** says what holds
  the app and how to release it.
- `github_app_not_configured`, `github_app_key_invalid` or
  `installation_token_failed`: a fault on the platform's side in reaching
  the app's repository through the platform GitHub App, which only a
  platform admin can fix. Change nothing in the repository and don't retry
  in a loop; tell the user plainly, and send the request where
  `inno-manage-app`'s **Asking a platform admin** says.

## Deployment types: `container` (below), `function`, `mcp-function`, `mcp-container`

Most of this skill describes the **`container`** type (a Docker container the
platform's host runs behind the front door). The other three differ from it
in ways one contract section each states; read the one for the app's type:

- **`function`** (§1.1): the app is its own Cloudflare Worker, in the
  platform's app namespace behind the *same* front door. Its entry is
  `app/index.ts` exporting
  `export default { fetch(request, env, ctx) }`, with no port, no `EXPOSE`
  and no Dockerfile (`inno-containerize` does not apply). CI bundles it in a
  job that holds no credential, and the platform uploads the bundle itself,
  setting every binding, the compatibility settings and logging; what the
  bundle may hold is the **Node apps** paragraph below. Its storage is the
  app's **own bindings**, `env.DATA` (D1) and `env.FILES` (R2), instead of
  `http://storage.internal`. `GET /healthz` is a **route** in the `fetch`
  handler, answering **exactly 200**. Every npm package it imports is
  declared as the **Node apps** paragraph below says.
- **`mcp-function`** (§1.1 and §1.2): a function app whose consumer is an MCP
  client instead of a browser. It serves the MCP **Streamable HTTP**
  transport at `POST /mcp`, stateless (no `sessionIdGenerator`), and has no
  browser sign-in and no sign-out link: the platform is the OAuth
  Authorization Server and the front door the Resource Server, so never read
  the `Authorization` header or route `/.well-known/oauth-protected-resource`
  yourself. Identity is still the front door's headers (**Identity** below).
- **`mcp-container`** (§1.3): that same MCP contract from the container
  shape, for a non-TS/JS stack or work a Cloudflare Worker can't host. The
  Dockerfile rules are `inno-containerize`.

Identity (read the header, never build auth), ephemerality, the protected
and injected files, and the safety-gate discipline below are **identical**
across the types (the sign-out link applies to the browser app types
only, wherever the app shows who is signed in). The
rest of this skill's code examples are the container reference; translate
them into the `fetch` handler for a function or mcp-function app.

## Releases: push = checks, tag = deploy

A push to the default branch runs the platform's safety gates and deploys
NOTHING: push work in progress freely; that run is the safety preflight
(`inno-safety-preflight` narrates it). Deploys happen only when a `v*`
release tag is pushed (`inno-ship` handles versioning and tagging).

## Stack: the user's choice; Python/Starlette is the tested path

Any stack that meets §2 is acceptable, and **no CI gate checks the language
or framework** (§4, the stack policy). **Python/Starlette is the tested
stack**: the template's reference app (`app/main.py`, plain Starlette) uses
it, so choosing it means starting from a known-good working example.
**Alternative stacks are equally fine.** This holds for new and migrated
apps alike (`inno-migrate-app` keeps the original stack by default): don't
"correct" an app to Starlette in either direction.

Whatever the stack, pin dependencies in its own manifest under `app/`
(`requirements.txt` for the Python reference, where the template's copy is
the source for its pins; `package.json` for Node; `go.mod` for Go) and keep
them CVE-clean: the `deps` and `container` gates fail the build otherwise.
R8 says what each gate audits, and §4 names the known FastAPI trap: check
that the lockfile resolves a clean Starlette before committing to it.

**Node apps: commit `app/package-lock.json`, and declare every import.**
§1.1's **Dependencies** bullet and R8 are the rule; this is how to follow it:

- In a function-shaped app (`function`, `mcp-function`), every package
  your Worker imports by bare name is listed in `app/package.json` itself,
  under `dependencies`. Nothing is installed at the repo root, a
  `node_modules` committed there or in `app/` is removed before the
  install, and CI installs with `--omit=dev`, so only what your lockfile
  names reaches the bundle: an undeclared import fails the bundle, and
  so does one listed only under `devDependencies`, with an error titled
  `devDependency imported at runtime` naming the package. Move such a
  package with `inno-ship`'s **Moving a devDependency into dependencies**,
  which keeps its specifier and its locked version. A container app's
  Dockerfile builds its own runtime tree, but list its runtime imports
  under `dependencies` too: the `deps` gate audits only those (R8).
- A function-shaped app's Worker is one bundle. JS, TS and JSON are bundled
  into its one script; text files (`.txt`, `.html`, `.sql`), data files
  (`.bin`) and WebAssembly (`.wasm`) ride beside it as modules, the only
  module types the platform takes; and an import of any other kind of file
  (an image, say) fails the build. The whole bundle is at most 16 MiB
  before compression, and Cloudflare's own script limit applies after
  compression as well (§1.1). Keep large data in the app's file storage,
  not in imported files.
- Regenerate the lockfile with `npm install` inside `app/` whenever you
  change dependencies, and commit both files together. A function-shaped app
  (`function`, `mcp-function`) that ships `app/package.json` must commit
  `app/package-lock.json`: the `app-build` job fails, naming the file, when
  it is missing or out of step. That job installs and bundles the app on
  **every push to the default branch**, so the preflight catches a missing
  lockfile, an import that does not resolve, a devDependency used at
  runtime, a symlink out of the repository and a bundle over 16 MiB before
  you tag. The `deps` gate refuses a function-shaped app's `app/package.json`
  with no committed lockfile as well.
- A container app should commit it too: while an admin has the release-age
  cooldown on (`safety.min_release_age_days` above 0), an app shipping
  `app/package.json` with no committed, parseable `app/package-lock.json`
  fails the `dep-age` gate, because ranges have no single publish date to
  check.
- The cooldown dates a function-shaped app's `dependencies` alone, since
  its build never installs `devDependencies`, and a container app's
  `devDependencies` too, since its Dockerfile may install them.
- That app-owned lockfile under `app/` is fine; a lockfile at the **repo
  root** is not (**Files you must not touch** below).

## Rendering: escape by default, never string-built HTML

Whatever the framework, **never build HTML with string interpolation or
concatenation**. The current user's identity (`X-Forwarded-User`) is
attacker-influenced input (anyone who can reach the front door with a valid
sign-in controls their own email string, and it flows straight into your
pages), so unescaped interpolation is a stored or reflected XSS that the
`sast` job's semgrep OWASP scan and human review both reject. That scan
covers the whole repository except the platform-owned root `src/` and the
directories semgrep skips by default at any depth (`test/`, `tests/`,
`build/`, `dist/`, `vendor/` and `node_modules/`), so your Dockerfile,
`.github/workflows/deploy.yml` and any root-level script are scanned too;
R8 is the authoritative scope. Use your stack's auto-escaping template
engine. In the Python reference, `Jinja2Templates(directory="templates")`
autoescapes by default: route all dynamic content through
`templates.TemplateResponse(request, "page.html", {...})`.

**Response headers.** A browser app (`container`, `function`) should
send a baseline of security headers on its HTML responses (§3), set in one
middleware in the app so they travel with the code through the gated
deploy. `get_app_security` §9 is the one place that names each header and
gives a starting Content-Security-Policy per deployment pattern, including
how an SPA allows its bootstrap script: take the headers and the policy
from there, not from memory. For a `container` app the CI run's
response-header report shows what the app sends today; R8 says when it runs
and that it never blocks a deploy.

**Files someone uploaded.** Serve a file a person uploaded back only as a
download, never inline, with three headers: `Content-Disposition:
attachment; filename="<name>"` (each character of the name outside
`[A-Za-z0-9._-]` replaced by `_`), `X-Content-Type-Options: nosniff` and
`Content-Security-Policy: sandbox`. The rule holds from any host, a public
one included: every app shares one site, so an uploaded HTML or SVG file
shown inline could run script beside every other app, in a signed-in
person's session. It covers a visitor's submission, a file an editor app
republishes (the two-app pattern's editor publishing a visitor's upload),
and every file read through a data link. The template's storage client
returns the three headers from `file_download_headers` (`fileDownloadHeaders`
in `lib/storage.js`); a function app sets the same three itself. The rule's
home is `get_app_security` §3.

## Accessibility: native elements first

Every browser app (`container`, `function`; the two MCP types have no
browser UI) should meet WCAG 2.2 Level AA (§3), and a school or unit with
its own accessibility policy is governed by that policy. **Fetch the
`get_app_accessibility` MCP tool before writing UI code**: it is the live
source for what that takes. The habits below cost nothing up front, and
they are a reminder, not a substitute for the served notes:

- **Native elements first.** A `<button>` for an action, an `<a href>` for
  navigation, a visible `<label for>` on every input, a native `<dialog>` for
  a modal.
- `<html lang>` and a specific `<title>` on every page, one `<main>`, and
  headings in order.
- **Visible focus.** Never remove the focus outline without a
  `:focus-visible` style in its place.
- **Single-page apps:** a route change updates `document.title` and moves
  focus to the new view.

None of this is a gate by default. For a `container` app the CI
accessibility report runs against the built image, and whether it can fail
the deploy is the app's `safety.a11y.mode`, which a platform admin sets: the
served notes' mode table says what each mode does, and
`inno-safety-preflight` reads the report. A `function` app gets no automated
report, so a review against the served notes is its only check.

## Persistence: the storage client, never local disk

Container disk is **ephemeral**: it is wiped on every restart and every
redeploy (R6). Never write a local SQLite file, never `open(path, "w")` app
data to disk. Use the storage client shipped in the template
(`app/storage.py`):

```python
from starlette.responses import JSONResponse, PlainTextResponse
from storage import Storage, current_user

db = Storage()

# a POST route, since it writes: Route("/visits", visits, methods=["POST"])
async def visits(request):
    user = current_user(request)
    if user is None or user["subject"] is None:  # a route that needs a person
        return PlainTextResponse("no signed-in user", status_code=403)
    owner = user["subject"]
    await db.execute("CREATE TABLE IF NOT EXISTS visits (owner TEXT PRIMARY KEY, n INTEGER)")
    await db.execute("INSERT INTO visits (owner, n) VALUES (?, 1) ON CONFLICT(owner) DO UPDATE SET n = n + 1", [owner])
    rows = await db.query("SELECT n FROM visits WHERE owner = ?", [owner])
    return JSONResponse({"visits": rows[0]["n"]})
```

The caller is read and "no user" handled before any per-person query, and
the rows are keyed on the caller's `subject`, as the **Identity** section
below says. A route that changes state is never a
GET, and on a browser app it also takes the origin check `get_app_security`
§12 sets.

`Storage()` defaults its base URL to `http://storage.internal`, which the
platform's host intercepts (the container's outbound handler) and routes to
the app's own D1 database and R2 bucket. **Leave `INNO_STORAGE_BASE` unset
in production**, where that default is correct. A local run of the container
has no host around it, so it has no storage either: its storage calls fail
unless `INNO_STORAGE_BASE` points at a local stand-in that serves the same
endpoints (R5). Never point it at the app's public address. File storage is
`put_file`/`get_file`/`list_files`/`delete_file` against the same client,
backed by R2. Non-Python stacks call the plain-HTTP endpoints R5 lists
directly.

A data link (`link_app_data`, contract §2.1) gives the consumer the source
app's database **and its files**. The same client reaches the source's
files with `put_linked_file`/`get_linked_file`/`list_linked_files`/`delete_linked_file`
(`putLinkedFile`/`getLinkedFile`/`listLinkedFiles`/`deleteLinkedFile` in
`lib/storage.js`), on the `/_storage/linked/{source}/files` routes beside the
linked SQL ones; a function app reads them as the binding
`env.LINK_FILES_<SOURCE>` beside `env.LINKED_<SOURCE>`. The grant is
read-write over the source's database and every one of its files, and on a
public source a write is published at once. A file someone uploaded is
served back as **Files someone uploaded** (under **Rendering**, above)
says, wherever it is read from.

A listing can be partial. `list_files` returns the keys as an ordinary list
that also carries `truncated`, which is true when the platform's host
stopped listing at its cap (R5 gives the cap), so the keys are only part of the
bucket: track keys in D1 rather than walk a bucket that size. The JS
client's `listFiles` returns an array with the same flag, not enumerable,
so deep equality and JSON see only the keys. A repo created from an older
copy of the template has a listing with no `truncated`: reading it raises
`AttributeError` in Python, and in JS it is `undefined`, so a partial
listing reads as complete. Check the repo's `app/storage.py` or
`lib/storage.js` before relying on the flag, and if it lacks it, copy the
current one from the template repo (the `Template repo:` line of the status
you read in the Version gate). The current client keeps the old shapes but
one: its identity helper (`current_user`, or `currentUser` in JS) answers no
user for a caller with no identity where an older one answered an empty
email, and its answer adds `member` and `subject` (**Identity** below). So
after the copy, make every place that reads the helper handle no user first.

**Two body caps on that storage API, and the SQL one is the easy one to hit**
(R5 is authoritative for both). A `{sql, params}` body over **4 MiB** (on
the SQL endpoints, and on the `/_storage/linked/{app}/sql/*` twins a data
link exposes) is refused `400 bad_request`, exactly the answer malformed
JSON gets, so an oversized bulk insert reads as a syntax error rather than a
size problem: send it in batches. A file `PUT` whose declared
`Content-Length` is over **25 MiB** is refused `413 too_large`, and one sent
with no `Content-Length` at all (a chunked body, for example) is refused
`411 length_required`, so an upload route checks the size itself, with its
own message, and sends the body with its length. Neither applies to a function-shaped app, which reaches
`env.DATA`/`env.FILES` with no host in between.

## Identity: read the header, never build auth

The front door decides who reaches the app, by its audience (members-only,
internal or public), and tells an identity-aware app who the caller is, in
the identity headers. R3 (`get_app_contract` with `sections: ["R3"]`) is
the authoritative text for every header the front door owns and for the
kinds of caller an app serves; this is how to apply it. Decide per request
what each kind of caller may see and do, and never assume a caller is a
member. **An
anonymous app is never told who the caller is**, at any audience: its rule
is R10, below (**An anonymous app: R10**), and the rest of this section's
helper and header guidance is for identity-aware apps.

Read the caller through the template's identity helper:
`current_user(request)` in `app/storage.py` (Python),
`currentUser(request.headers)` in `lib/storage.js` (a JS or TS container),
and `currentUser(request.headers)` from `app/identity.ts` in a `function` or
`mcp-function` app. Each answers no user (`None` in Python, `null` in
JavaScript and TypeScript) when `X-Forwarded-User` is empty or missing, and
otherwise `{ email, groups, member, subject }`, where `member` is true
exactly when a group ends `-users` (the caller holds the app's members
group) and `subject` is `X-Forwarded-Subject`, the person's identity
provider ID (`None` or `null` when that header is empty or missing; a
subject alone never makes a user). A stack with no helper reads the headers
by the same contract. Check the repo's helper before relying on that
answer: an older one has no `subject`, or answers an empty email rather
than no user (below). In a route that needs a person, handle no user first,
and a missing `subject` with it, before any per-person read or write:

```python
user = current_user(request)
if user is None or user["subject"] is None:  # a route that needs a person
    return PlainTextResponse("no signed-in user", status_code=403)
```

**Never default the absence back into a value** (`or ""`, `?.email`,
`?? ""`, `"unknown"`): a placeholder bound into `WHERE owner = ?` is one key
that every caller with no identity shares, and a SQL `NULL` is no better.
The helper answers no object at all, so code that reads the email without
the check fails rather than share a key; keep it that way. Contract §3 is
the authoritative text for this rule.

Refuse a caller with no user only in a route that needs a person, never in
a middleware or ahead of routing: the platform's health probe,
`GET /healthz`, arrives with empty identity headers (R3) and must get its
200 (R2). In a route that needs a person, the branch is the one-line refusal
above. **An MCP app refuses inside MCP**, with a tool result marked as an
error or a JSON-RPC error, never with an HTTP status: §1.2 and §1.3 make it
a MUST and say why.

A repo made from a template older than platform v0.17.0 has an older
helper with no `subject`; one older than v0.16.19 also answers an empty
email rather than no user and has no `member`, and a function-shaped repo
from then has no `app/identity.ts`. Copy the current helper from the
template repo (the `Template repo:` line of the status you read in the
Version gate), as **Persistence** above says for the storage client. Where
that template has no such helper either, read an empty or missing
`X-Forwarded-User` as no user in the app's own code, and the subject from
`X-Forwarded-Subject`, by the same rule.

- `X-Forwarded-Email` carries the same email as `X-Forwarded-User`: the
  front door injects both, so either one works and neither is more
  authoritative. Read `X-Forwarded-User` by default and treat
  `X-Forwarded-Email` as its alias if you see it in a request dump.
- **Key per-person data and roles on `X-Forwarded-Subject`, never on the
  address.** Both address headers carry the caller's email address, which
  can change for one person and pass to another: the platform admits a
  member by the identity provider account their grant is pinned to, but
  anything your app keys on the address, its own data or its own role
  store, still goes to whoever holds the address. `X-Forwarded-Subject`
  stays with the person and comes with every identified request, on every
  app type (R3). §3 recommends keying on it, so a new app
  does from the start. An existing app keyed on the address may re-key its
  rows once, since every identified request carries both headers: a
  migration in the app's own code, recommended and not required (§3).
- **`X-Forwarded-Groups`** carries at most one group, this app's own
  members group, and only when the caller is a member; every other request,
  a signed-in non-member of an internal app included, carries no group (R3's
  group rule). The group's name is in the `App groups:` line of the status
  you read in the Version gate, with the app's name in place of `{app}`. It
  never carries the platform admin group, another app's groups, or any
  other group, so use it only to tell a member from a signed-in non-member
  (the helper's `member` is that test); any finer role (an editor, a staff
  view, an in-app admin) needs your own role store keyed on
  `X-Forwarded-Subject`, and only for a caller who has one.
- **An empty identity is no user: an expected caller, not a fault, and
  never a member or a key.** The platform's health probe (`GET /healthz`),
  and every request to an anonymous app, arrive with the four identity headers present and
  empty (R3; on an identity-aware app the probe is the only request that
  does), and a request that never passed the front door (the app run
  locally, a test) can carry none; the helper reads each as no user. A
  person the platform refuses never reaches your code: the front door
  answers them itself. On a browser app that is a plain 403 "No access"
  page, or a 503 "Try again shortly" page when it cannot ask the platform;
  an MCP app's caller gets a 401 with a bearer challenge instead, which
  sends their MCP client back to authorize.
- **How fast a change reaches the header** is R3's to state: within the
  front door's cache, at most 60 seconds on an MCP app and 10 seconds on a
  browser app.
- **The platform signs people in, outside your code.** On a members-only or
  internal browser app the front door sends a person with no session through
  the platform's own
  sign-in and back to the page they asked for (R3 says how, and how long a
  session lasts). Two things that reach an app's own pages: once the
  session has ended, anything but a top-level GET page load, a form POST
  included, gets a `401` rather than the sign-in redirect, so a background
  request (a `fetch`) that meets a `401` reloads the page to sign in again,
  and a form posted then loses what it carried; and a sign-in never starts
  inside a frame, so a page of the app framed by the app's own page, with
  no session, shows a "Sign in" page whose link opens the app's root
  address in the whole window (another page's frame of the app is refused:
  **No browser calls or frames between apps**, below). What people see
  is the platform docs' **Signing in and out: what people see**
  (`get_platform_docs`).

The front door also sets three proxy headers you may trust:
`X-Forwarded-Host` (the hostname the request arrived on; build links from
it), `X-Forwarded-Proto` (always `https`) and `X-Forwarded-For` (the client
address from Cloudflare's edge, removed when unknown). It deletes
`Forwarded`. Every other header, including `X-Real-IP`, `True-Client-IP`
and `X-Forwarded-Port`, reaches you exactly as the client sent it: never
use one for identity, origin or an access decision.

**The platform's cookies and paths never reach your app** (R3). The front
door keeps its own cookies out of the `Cookie` header your app receives,
answers every `/_auth/` path on the app's host itself, and drops a
`Set-Cookie` from your app that names one of its cookies. Because every
app host shares one parent domain, it also drops any `Set-Cookie` that
carries a `Domain` attribute, even one naming the app's own host, and
strips a `Clear-Site-Data` header. So keep your cookies host-only (no
`Domain`), route nothing under `/_auth/`, and never rely on
`Clear-Site-Data`.

**Every cookie your app sets** carries the `__Host-` prefix (so `Secure`,
`Path=/` and no `Domain`) and is `HttpOnly` unless the app's own script
must read it: every app shares one site, and a page on another app's host,
a public one included, can shadow any other cookie with one of its own.
This is R10's cookie rule, its paragraph **Every app's own cookies**, which
binds every app's cookies, an identity-aware app's included (R3 says so
too); `get_app_security` §9 states the same rule.

**WebSockets and event streams** (R3). The front door refuses a WebSocket
upgrade from another origin's page, a sibling app's included, so your app
need not check `Origin` itself, and no endpoint may rely on another
origin's pages opening it. On a members-only or internal browser app an open WebSocket or event stream ends
when the person's session does: design for reconnect-and-catch-up (§5).

**No browser calls or frames between apps** (R3). On a members-only or
internal app the front door refuses every request from another page, on the
site or elsewhere, that is not a plain link (a top-level GET navigation), so
never have one app's page frame, include or call another app (a frame, a
script, a stylesheet, an image, a `fetch`, a form post), and when an app
needs another app's data, read it through a data link (`link_app_data`,
contract §2.1), on the server.

**Never implement login pages, sessions for signing people in, password
storage, or an "auth disabled" dev path**: the front door strips inbound
copies of the headers it owns before injecting its own values, so there is
no spoofing surface as long as you don't add one. A missing user is no user
in local dev too: send the headers yourself (**Keep
`ENVIRONMENT=production`** below) rather than default the absence into a
value. An anonymous app's per-visitor state (below) is not a sign-in
session: it never identifies anyone.

### An anonymous app: R10

The contract's rule for an app registered `anonymous`, R10
(`get_app_contract` with `sections: ["R10"]`, the authoritative text), opens:

> **R10: An anonymous app keeps nothing per person**
>
> An app registered with
> `identity: "anonymous"` is never told who its caller is, at any audience
> (R3): the four identity headers arrive present and empty on every request,
> and no `X-Caller-Assertion` arrives, so it has no Connections (§2.2). Only an
> anonymous app can be public. No accounts, no per-person views, no keys or
> limits taken from a person. What a visitor submits is stored and never
> rendered. Per-visitor state (a cart, a multi-step form, a vote already cast)
> lives in the app's own cookie or under a random cookie key, is never an
> identity, and follows APP-SECURITY's forged-request rules. The app may be
> public.

So the app reads none of the identity headers, keys nothing on them, and
shows no sign-out link (it never shows who is signed in, so R4 asks for
none). R10 goes on to every app's cookies (above), where the promise ends
(below) and a site with a signed-in part, which is two apps (the
`inno-new-app` skill's `references/two-app-pattern.md`).

- **Per-visitor state** takes the cookie rule above (`__Host-`, `HttpOnly`
  unless the app's own script reads it), and a state change is accepted
  only from the app's own pages (`get_app_security` §12).
- **Submissions** are stored and never rendered by this app; whatever reads
  them (an identity-aware editor, the two-app pattern's) protects them in
  its own code, and serves any uploaded file as **Files someone uploaded**
  (under **Rendering**) says.
- **Where the promise ends** (R10). While the app is members-only or
  internal, people still sign in to reach it, and the platform knows who
  did (its admins and its audit log), though the owner's panel shows
  sign-in counts, not people; a public app's visitors never sign in. The
  platform does not tell the app who the caller is, and it does not make
  visits unlinkable against an owner who tries: the app still sees each
  caller's address (`X-Forwarded-For` and `CF-Connecting-IP`) and the
  timing of each request, small counts can single a person out, and an
  identity-aware app of the same owner on the site can link a visit to a
  person. Say so plainly to an owner who promises anonymity.
- **No Connections**: there is no user to hold one (**Per-user backend
  access**, below).

## Configuration & secrets (Variables)

App-level values (one API key the whole app shares, a base URL, a feature
flag) are **Variables**: set once with `set_app_variables` (or the app
page's Variables tab), delivered to your running code as ordinary
environment variables. Read them the normal way for your shape:
`os.environ["MY_KEY"]` / `process.env.MY_KEY` in a container app,
`env.MY_KEY` off the fetch handler's `env` in a function-shape worker.
Never commit them (`gitleaks` fails the build on the full history) and
never build a settings page to collect them. Names, secrecy and timing are
§2.3's and `set_app_variables`' description to state; the one that touches
code is that on a container app a change starts a new container instance
on the next request, as a platform release that moves the host build does
too (§2.3), so the app must come up clean on any request. A route that
spends an app-level key needs the limits `get_app_security` §5 sets, per
client and globally.

An app may describe the variables it reads in `app/inno-variables.json`;
§2.3's **Declaring what an app wants** is the format and its rules. Write
one whenever your app depends on a variable an owner wouldn't otherwise
know to set: a required name with no value then shows as missing in
`list_app_variables` and the panel's Variables tab, and `app_status` names
it. Two things to know when you edit it. A file that breaks a rule is
refused whole while the deploy stays green, and the reason surfaces in the
run log (`inno-ship`'s **Declared variables** section says where). And
deleting the whole file does not clear the declarations: commit it as `{}`
instead.

## Per-user backend access (Connections)

Identity above is about *your app* knowing who's using it. Some apps also
need to call **another** service *as that same person* (a per-user API or
SaaS account the app fronts: a departmental system, a niche tool, a dev
instance). For that, use a **Connection**, never a single hardcoded
credential shared by every user. The dividing line: if every user of your
app would reach the backend with the exact same key, that's a plain app
secret, a **Variable** (above), not a Connection; if the backend tells your
users apart, it's a Connection.

Connections are reachable from **`mcp-container`** apps only in v1; the
other three types can't consume one yet, and `set_app_connection` refuses
them with `app_type_unsupported`. They are for **identity-aware**
apps only: an anonymous app is never told who its caller is, so no user of
it can hold one, and `set_app_connection` refuses it with `app_anonymous`
(§2.2). Setting one up (discovering how
the backend signs people in, choosing among the three strategies, calling
`set_app_connection`) and wiring the code that consumes it (the template's
`connections.get(name, callerAssertion)` helper, every seam answer the code
must branch on, and what to do when the repo's template client is older)
is a full workflow of its own: use the `inno-add-connection` skill rather
than wiring this ad hoc. The rules the code must hold are §2.2 and
`get_app_security` §8. Two rules shape every line of that code:

- Read the inbound `X-Caller-Assertion` header off the request you are
  serving and pass it straight through to the seam; never keep, persist or
  log it.
- Use the returned credential for the backend call at hand, and never write
  it to disk, a database row or a log line. Whether the app may keep it in
  memory between calls, and keyed how, is `get_app_security` §8's rule: one
  person's credential never serves another person's request. On
  `NotConnected`, relay its `connect_url` to the user; on
  `ConnectionLocked` (a subclass of `NotConnected`, so catch it first), tell
  them to **re-authorize this MCP client** (in Claude: `/mcp`, then
  re-authenticate that server), never to reconnect the backend, which
  loops.

## Sign out: one link, no session code

Whenever a browser app shows who is signed in, it links to
`/_auth/signout` on its own host (R4; a footer is fine):

```html
<a href="/_auth/signout">Sign out</a>
```

Show it only when the helper returns a user, as the template's pages do; an
app that never shows who is signed in needs no link, and an anonymous app
never does. Make it a plain link
the person clicks, never a `fetch`, a frame or a prefetch: R4 says why, and
what signing out ends, which is the person's panel and every app session
they hold on the platform, in every browser, and their identity provider
session in the browser they sign out in. So label it plainly ("Sign
out"), never as signing out of this app alone. The path is the same on
every app and every instance, so there is nothing to look up, and `/_auth/`
is the platform's on every app host (R3): route nothing under it yourself.
An app made before platform v0.17.0 links to the old sign-out address and
changes that link once (the contract's version 34 note, `get_app_contract` with
`history: true`). What people see when they sign in and out is the platform
docs' **Signing in and out: what people see** (`get_platform_docs`).

## Logging: stdout, one event per line

Log like it's a contract: one event per line to stdout, plain text or JSON
(§3). That stream is what surfaces in the app's panel **Logs tab** and the
`get_app_logs` MCP tool, whose description says what each line carries and
how its source column tells your container's lines (`container`), the
platform's front door lines (`front door`) and a Worker's lines apart. Log
well now and runtime debugging (`inno-manage-app`'s Runtime
issues guidance) is actually useful later instead of a wall of noise.

## Keep `ENVIRONMENT=production`

There is nothing for you to configure here. The platform sets `ENVIRONMENT`
to `production` itself, with every other binding, when it uploads a function
app's Worker, and a container app's host is the platform's own (R7, and
`get_platform_docs`'
**Environment & config integrity**). No wrangler config may live in your
repo (below), and `ENVIRONMENT` is a reserved Variable name that
`set_app_variables` refuses. For local dev, pass mock identity headers
straight to the locally run container, and try each kind of caller R3
names; never add an "auth disabled in dev" code path. An anonymous app
tries the last one alone, since every request it gets looks like that:

```bash
# A member: the members group from the App groups: line of the status.
curl -H 'X-Forwarded-User: user@example.com' -H 'X-Forwarded-Subject: user-id' -H 'X-Forwarded-Groups: <members group>' http://localhost:8080/
# Signed in but not a member, as an internal app gets one: no group.
curl -H 'X-Forwarded-User: other@example.com' -H 'X-Forwarded-Subject: other-id' -H 'X-Forwarded-Groups;' http://localhost:8080/
# No identity, as the front door sends the health probe and every request to an anonymous app: the headers present and empty.
curl -H 'X-Forwarded-User;' -H 'X-Forwarded-Subject;' -H 'X-Forwarded-Groups;' http://localhost:8080/
```

## Files you must not touch

The platform installs its own build tools when CI builds your app, from its
CI mirror, into a directory of its own outside your checkout, and supplies a
function app's bundling config, so **none of the following may exist in your
repo at all**. R7 is the authoritative list,
with the reason for each; the `config-integrity` gate fails outright,
naming each path it finds ("delete `<file>`: the platform injects ...").
Never create or restore one locally, even to "match the template": there is
no version of these files that belongs in your repo.

- `src/`, all of it, at the repo root. The platform owns that directory, so
  the gate fails a repo with anything of yours under it (a source file,
  `src/node_modules/`, `src/package.json`, `src/tsconfig.json`) with a
  "delete src/" message. An empty `src/` passes. Put your code under `app/`;
  an `app/src/` directory is yours and fine.
- `package.json` and its lockfile (`package-lock.json`) **at the repo
  root**: nothing is installed there. Your app's own build files under
  `app/` (a Node app's `app/package.json`, etc.) are yours and fine.
- `tsconfig.json`, repo root only, same rule. For a function-shaped app CI's
  build places the platform's `tsconfig.json` at the repo root before it
  bundles, because the app Worker builds from your checkout; that copy is
  the platform's, and a committed one still fails the gate.
- `wrangler.jsonc`, any competing `wrangler.json` or `wrangler.toml`, and a
  `.wrangler/` directory. Wrangler's config discovery order means an
  unvetted `wrangler.json` would silently take priority over the config the
  platform supplies anywhere discovery decides which config to read.
  The build pins its wrangler call to an explicit config, and the gate
  rejection is the independent belt to that pin.
- Root-level `.env` / `.env.*` files: wrangler loads them when it runs at
  the repository root, as it does to bundle a function app and to push a
  container app's image, and adopts every key the step did not set, so a
  committed one (an app-set `CLOUDFLARE_API_BASE_URL`, say) would redirect
  the build's own calls.
- Every package manager's project config at the repo root: `.npmrc`,
  `.yarnrc`, `.yarnrc.yml`, `.pnpmfile.cjs`, `pnpm-workspace.yaml` and
  `bunfig.toml`. A `.npmrc` is rejected at **any** depth, `app/.npmrc`
  included, because npm expands environment variables into it, which makes
  it a credential-exfiltration channel. The other package managers' files
  are allowed inside `app/`. Install from the public registry and never
  commit a `.npmrc` anywhere.
- A `scaffold/` directory. Registration prunes the template's
  deployment-type scaffolds out of your repo, best effort, so a surviving
  `scaffold/` means the prune did not happen and the repo is carrying both
  variants' files. While `app/.needs-build` is present the directory is
  allowed (an unbuilt repo can run CI before a prune lands), and
  `scaffold-check` skips that run's deploy anyway; deleting the marker to
  start building re-arms the check, so delete `scaffold/` with it. When
  `register_app` warns that the repository's `scaffold/` has no overlay for
  its type, or answers `scaffold not applied`, follow what it says.
- **A directory symlink anywhere in the repo**, at any depth and dangling
  ones too, and **a file symlink whose target resolves outside the
  repository**. A file symlink that resolves inside the
  repository (an alias such as `alias.ts -> real.ts`) stays legal. The gate
  walks your tree without following links, so anything behind a directory
  link (an `app/.npmrc`, say) would never be inspected, and the build reads
  a linked file's bytes, so a link out of the repository could bake files no
  gate saw into your app. `config-integrity` has no policy toggle, so a repo
  carrying one cannot deploy until the link is removed. A function app's
  build refuses a link that points outside the repository, or nowhere,
  anywhere in the checkout, `node_modules` directories included (the gate
  does not walk them), where an installed package or a `file:` dependency
  can put one: a link may name only a file inside your repository.

Keep secrets and local env out of the repo entirely: an app-level key or
config value belongs in a **Variable** (`set_app_variables`, or the app
page's Variables tab), delivered to your code as a real environment
variable.

The one file checked by content rather than by absence is `CLAUDE.md`: the
gate checks that five headers from the template are present (the rest of
the file is yours to extend). **The header check is type-blind.** Three
headers are required of every app, whatever its type:
`## Innovation Platform App`, `## Identity (do not build auth)` and
`## What CI enforces`. The remaining two are variant groups, and ANY member
of a group satisfies the gate: `## Persistence (use the storage client)` or
`## Persistence (use your bindings)`, and `## Container contract` or
`## Function contract`. The retired `## Worker contract` heading no longer
passes: an app still carrying it renames it `## Function contract`. The
gate never asks what type your app is, so a container app carrying the
function headers passes, and the reverse passes as well. Which of the
template's eight guides to start from (one per type, and an anonymous one
per type), and how to merge the headers into a `CLAUDE.md` a repo already
has, is `inno-new-app`'s `references/hand-authored-layout.md`.

Everything under `app/` (routes, templates, requirements, your own modules)
is yours to change freely.
