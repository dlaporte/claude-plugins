---
name: inno-new-app
description: Use when the user wants to create a new app on the Innovation Platform ("new app", "create an app", "start a project on inno-platform"). Guides intake, creates a repo from the instance's template repo in the user's own account, calls register_app, commits the proof-of-control file it names and has them install the platform GitHub App, calls register_app again to provision + bind it, then scaffolds app/ per platform-conventions.
---

# inno-new-app

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

Creates a new Innovation Platform app end to end: intake -> the user creates a
repo **they own** from the platform template -> `register_app` (first call)
-> commit the proof-of-control file it names + install the platform GitHub App
-> `register_app` (second call) provisions + binds it -> pull + scaffold. Requires the
`inno-platform` MCP server (ships with this plugin's `.mcp.json`) to be
connected. The first call to any `inno-platform` tool triggers a browser
sign-in through your organization's identity provider. That's expected, not an
error: wait for it to complete. **If the
connector wasn't already authorized when the session started, waiting isn't
enough**: mid-session authorization alone does not expose the tools (the MCP
client enumerates tools at startup); the user must authorize it AND you must
restart the session before calling any `inno-platform` tool.

**The repo is the USER's.** There is no platform-owned repo model anymore. The
repo lives in the user's **own** account or org, created from the instance's public
template repo (the `Template repo:` line of the status you read in the Version
gate), with the platform's GitHub App installed on it; `register_app`
finishes the job. The platform never creates a repo on the user's behalf.

**What is genuinely user-only.** Exactly two steps in this flow require the user
personally: **installing the platform GitHub App** (§3: a third-party token
cannot install a GitHub App on someone's account) and any **browser SSO login**.
Everything else (creating the repo, committing the registration proof file,
cloning, scaffolding, committing, pushing, tagging, setting variables) you can
do with the user's own authenticated CLI and MCP tools. Never tell the user something "can't be done from here" unless it
is one of those two. Where the reason is judgment rather than capability, say
which: setting a *secret* variable is a **should not** (it would put the secret
in the conversation transcript), not a **cannot**.

**Already have an existing repo?** If the user wants to put a repo/codebase they
*already* have on the platform (not create a fresh one from the template), use
the `inno-migrate-app` skill instead: it registers the existing repo in place
and adapts it to the contract, with no scaffolding from the template.

**Speak the user's language.** Plain terms with the user, no provider or
product names unless they have shown technical fluency. The full rule is the
plugin README's **House style** section, and it applies to every user-facing
sentence in this flow.

**Asking a platform admin.** Where this skill sends the user to a platform
admin (a guardrails exception, a higher app limit, registration turned back
on), the request goes to the contact the platform names: the `Support:` line
of the status you read in the Version gate, when it has one.
`inno-manage-app`'s **Asking a platform admin** is the one home for that
rule.

## 1. Intake: ask the user for five things

1. **App name**: lowercase letters, digits, hyphens only, 3-29 chars,
   starting with a letter. This drives the app's **hostname** on the platform
   domain (the `App host pattern:` line of the status you read in the Version gate, with the app's name in place of `{app}`; `register_app`'s answer gives the real hostname), so keep it short and DNS-safe. It is NOT
   the repo name, which is the user's choice (see below). A handful of
   names are reserved server-side; `check_name` reports those, so don't
   enumerate or guess.

   **Verify availability before you settle on a name: never recommend or
   confirm a name without checking it first.** (This step is the plugin's one
   home for the name rules and the registration-time active-app check, whose
   rule is `inno-manage-app`'s; `inno-migrate-app` points here.) Call the **`check_name`** MCP
   tool (read-only; provisions nothing) on the candidate. Only proceed with a
   name it reports as **available**. If it comes back in-use, reserved, or
   invalid, ask the user for a different one; a name it refuses as unusable is
   echoed back inside `«»` guillemets, which fence it as untrusted text rather
   than marking it as quoted by the user. If it says the name **was
   recently purged and is held until** a UTC time, or that it is held until
   an app that read the purged app's data has been rebuilt or redeployed,
   nobody, admins included, can register it before then: offer a different
   name or wait.
   If it's the caller's *own* existing app, tell them that (a stopped app is brought back
   with `start_app`, not by re-registering it). If it is the caller's own
   **partially-provisioned** app, `register_app` resumes that registration
   rather than starting fresh: carry on at §3 with the repo it began with
   (another repo is refused `repo_mismatch`). For a platform admin the report
   names the owner when the app is someone else's, and `register_app` would
   resume someone else's partial registration for them: do that only when
   it is what the admin means to do. `list_apps` cannot prove a
   name is free, since an ordinary user sees only their own apps there: use
   `check_name`.

   **Active-app limit.** `check_name` also warns when the user is at their
   active-app limit. At the cap, `register_app` WILL fail with
   `app_limit_reached`, so resolve this BEFORE any build work. Report the
   limit factually and name the remedies, the rule `inno-manage-app` sets for
   `start_app`: the user stops one of their own apps when THEY choose to, or
   a platform admin raises their limit (`apps.max_active`, user scope). **Do
   NOT propose or offer to stop specific apps to make room**; that trade-off
   is the user's to initiate. If the user asks to stop one, `stop_app` it
   only with their explicit confirmation by name (stopping takes the app
   offline and starts its purge countdown; from platform v0.17.9 its address
   then shows visitors a page saying it is stopped). Otherwise stop here:
   an admin raising the limit, or not building the app, are the remaining
   options.
2. **Repo**: the `owner/repo` slug of the GitHub repo the user will create
   from the template (§2). The **owner is the user's** account or org, and the
   repo name is **their choice**: suggest the app name itself, but it
   is not required and can be anything. The repo may be public or private.
3. **One-line purpose**: becomes the app's `description` (at most 500
   characters; the tool schema rejects a longer one).
4. **Initial members' emails** (optional, can be empty): the addresses they
   sign in with, to grant access alongside the owner. The list can be added to
   later with the
   `inno-manage-app` skill's `grant_access`.
5. **Does the app need to reach another service *as each person using it*?**
   Not the sign-in in front of the app (the platform runs that for free on a
   members-only or internal app): this is about
   your app calling out to some *other* system that also tells its own users
   apart (a departmental system, a niche tool, a per-user account on some
   outside service). If yes, note it now: today that only works for an MCP
   server built the container way that is told who each caller is (it
   affects the type and the identity choices in §1b below), and
   once the app is registered you'll set it up with the `inno-add-connection`
   skill.

## 1a. Guardrails check: HARD STOP on conflict

Before confirming anything, call the **`get_guardrails`** MCP tool and evaluate
the proposed **name** and **purpose** against the platform's acceptable-use
policy. This is qualitative judgment (impersonation, misleading authority,
offensive names, prohibited purposes, data handling): apply the policy's
spirit, not just its examples. `register_app` requires you to pass
`accept_guardrails: true`, which asserts the app will follow these guardrails,
so do not pass it until you've actually done this review.

- **Clean** → proceed; no need to mention it unless the user asks.
- **Conflict** → do NOT call `register_app`. Name the specific policy line,
  explain the problem in one plain sentence, and help the user pick a compliant
  name/purpose. If they believe their use is legitimate anyway (e.g. sanctioned
  research), direct them to a platform admin for an explicit exception first:
  you cannot grant one, and you must not register the app without it.

Confirm the name, repo, purpose, and members back to the user before going
further: registration provisions real resources (a database, file storage
and the app's member list) and binds them to the user's repo.

## 1b. Design the app before registering

Before registering, produce and present a real design. The approval gate at the
end of this section is a hard one: `register_app` provisions real resources.

**Fetch the contract first:** call the `get_app_contract` MCP tool with
`sections: ["1", "1.1", "1.2", "1.3", "3", "4", "5"]`. Those sections carry
the four deployment **types** and their requirement deltas (§1.1 to §1.3),
the recommendations (§3), the stack policy (§4), and the deployment patterns
with what the platform does NOT support (§5: background jobs,
machine-to-machine APIs, guaranteed long-lived connections); the answer
opens with the contract version and the current recommended base images.
Evaluate the user's idea against it before designing; a
not-supported requirement surfaces HERE, not after registration.

For an app people will open in a browser (a `container` or `function`
design), **fetch `get_app_accessibility` beside it.** It serves the
platform's accessibility notes (WCAG 2.2 AA as the target; a school's own
policy governs where it has one), and its defaults shape the design's
Accessibility line below and the scaffold in §4. The two MCP types have no
browser UI, so it does not apply to them.

Invoke the **`superpowers:brainstorming`** skill to design the app: what it does,
its data model (what it stores: tables, files), its routes/pages, and its
access model (who can see and edit). If that skill isn't available in the
session, run an equivalent inline pass over the same points yourself. Either
way, the design still has to be written into your reply and approved (see
"Present the design, THEN ask for approval" below); the skill's absence is not a
reason to skip that.

The design includes four contract-informed choices that are **the user's to
make, with your recommendation**:

- **Identity**: ask the user, in these words, **"does the app need to know
  who each caller is?"** Yes is `identity-aware`, the default: the platform
  tells the app who each caller is, so it can keep per-person data and
  roles and use a Connection. No is `anonymous`: the app is never told who
  the caller is, at any audience, takes no Connections, and is the only kind
  of app that can later be made public (a public site or tool, a public MCP
  server, or an internal app that must not know who answered, such as an
  unattributed staff survey). An anonymous app follows the contract's R10
  (`get_app_contract` with `sections: ["R10"]`): no accounts, no per-person
  views, and what a visitor submits is stored and never rendered. Like the
  type, identity is fixed when the app is created: a different identity is
  a new app. If the user wants a public site with an editing area, wants to
  collect submissions from the public, or wants an existing app made public,
  that is **two apps**, an anonymous one and an identity-aware editor: read
  `references/two-app-pattern.md` and design both.
- **Deployment type**: `function`, `container`, `mcp-function`, or
  `mcp-container` (passed to `register_app`; the server defaults to
  container, but for a **greenfield** app you recommend and default to
  **`function`**, or **`mcp-function`**/**`mcp-container`** when the product
  is an MCP server). Pass only these four names. The four types:

  - **`function` (recommend for greenfield):** the app is its own Cloudflare
    Worker (JS/TS) behind the platform's front door: ms cold starts and no
    Dockerfile. This
    is the right fit for the common citizen-dev shape (a small web UI + JSON
    API in TS/JS).
  - **`container`:** choose this when the description gives a **clear signal**
    for it: an explicit **non-TS/JS stack** (Python, Go, Ruby, ...), **native
    dependencies** or system binaries, **long-running / heavy compute**, or a
    port of existing non-JS code (that's `inno-migrate-app`, which defaults to
    container). Absent such a signal, prefer function.
  - **`mcp-function`:** choose when the product is an **MCP server for AI
    assistants** (Claude Code, claude.ai) rather than a browser UI. It is
    function-shaped (JS/TS, no Dockerfile) and serves MCP at `POST /mcp`;
    users add the app's MCP address (the `App MCP address pattern:` line, with
    the app's name in place of `{app}`) as an MCP server in their client.
    **Stateless only** (§1.2): tools work normally, but server-initiated
    features (notifications, sampling, elicitation, long-lived subscriptions)
    do not; if the design needs those, it does not fit this type today, so
    surface that HERE, not after registration. Access is given and taken away
    with the same tools as the other types (`grant_access`, `revoke_access`,
    and `set_app_access` for its audience); there is no browser SSO, and
    §1.2 says what admits a caller. **One hard constraint:** if §1 flagged
    that the app must reach
    another service *as each person using it* (a per-user **Connection**),
    this type **cannot**: only `mcp-container` can consume a Connection in
    v1, and only on an identity-aware app. Choose `mcp-container` instead;
    do not land such an app on
    `mcp-function` and discover the gap after registration (the type is
    fixed at registration).
    **Idle clock:** an MCP app that is built and then left connected but
    unused is warned and then stopped like any idle app. What counts as use
    is served from one place, the **Lifecycle (idle clock)** section of
    `get_platform_docs`, and `inno-manage-app`'s lifecycle section points to
    it: fetch and quote that sentence rather than describing the rule in your
    own words. Tell the user when you hand the app over (`inno-manage-app`).
  - **`mcp-container`:** choose when the product is an **MCP server** that
    needs the **container** shape instead: a **non-TS/JS stack**, **native
    dependencies**, **heavy/long-running compute** a Cloudflare Worker can't
    give it, **or an MCP server that must consume a per-user Connection**
    (this is the only type that can, in v1, and only when the app is
    identity-aware; see `inno-add-connection`). It
    is `mcp-function`'s MCP contract (`POST /mcp`, **stateless only**, no
    browser SSO) on the container baseline (§1.3). Default stack: **Python +
    the official MCP Python SDK** (FastMCP), from a starter whose transport
    setting this skill's §4 says to keep.
    Note the idle **cold start**: a sleeping container wakes on request, so
    expect a seconds-scale delay on the first `POST /mcp` after idle (how
    long it stays up with no requests is the `container.sleep_after`
    setting, which `get_config app=<name>` shows once the app exists).
    Mention this if responsiveness matters to the user. The idle-clock rule
    under `mcp-function` applies here too, from the same served home.
  - State your recommendation and the reason, and go with the user's call.
- **Deployment pattern** (contract §5): server-rendered is the default for
  internal tools; SPA+API when rich client interactivity is the point. It
  applies to either browser type.
- **Stack** follows from the type: a **function** or **mcp-function** app is
  TS/JS (that is what Cloudflare Workers run; an mcp-function app builds on
  the MCP TypeScript SDK). A **container** app defaults to Python/Starlette
  (the tested container stack, with a working reference app; contract §4),
  or the user's chosen stack: any language is supported. An
  **mcp-container** app defaults to **Python + the official MCP Python SDK**
  (FastMCP), but any language is equally supported.

**Who may reach the app, its audience, is not a registration choice.** Every
new app starts **members-only**: its member list (the owner and anyone
granted access). Widening it later, to **internal** (everyone the identity
provider signs in, members or not) or to **public** (anyone on the internet,
with no sign-in, an anonymous app only), is `inno-manage-app`'s widening
review, run once the app is built and checked, never at registration. Ask
which audience the app is meant for in the end, so the design serves it
(an anonymous app is reviewed as public from the start, `inno-safety-preflight`),
and say plainly that it starts members-only.

**When the answer is internal or public, check now whether it is allowed.**
Whether an app may be widened is a platform setting a platform admin
controls: `access.allow_internal` (on by default) and `access.allow_public`
(off by default), each settable for the whole platform, for one owner, or
for one app. Before you design further, call `get_config user=<the user's
own sign-in address>` (ask for it if you do not know it) and read the
target's line, `access.allow_public = <value> [<where it came from>]` (or
`access.allow_internal`):

- **Allowed** (`true`): say so, and carry on; widening still happens after
  the app is built and checked.
- **Not allowed** (`false`): tell the user now, in plain words, that a
  platform admin has to allow it before the app can be widened, and that the
  admin can allow it for this one app once it is registered, or for all of
  the user's apps now. Offer to draft that request (`inno-manage-app`'s
  **Asking a platform admin**). The app can still be designed, registered
  and built while the request is pending; it simply stays members-only until
  the admin allows it. Never suggest working around it by granting access to
  everyone by hand.

An app-scope value set after registration wins over what you read here, so
this is an early warning, not the final answer: `inno-manage-app`'s widening
review reads the app's own value when the time comes.

### Present the design, THEN ask for approval

The user deserves to see what they're approving. **Write the full design into
your visible reply as a structured section, never a one-line summary buried
inside a tool-approval prompt.** An approval question that references "the
design as described" when no design appears in the conversation is a defect,
not a shortcut: the user cannot approve what they have not seen.

The written design covers, at minimum:

- **What the app does**: in the user's own terms, a short paragraph
- **Identity** (identity-aware or anonymous) and the user's answer to the
  identity question; for a two-app design, both apps and their roles
- **Deployment type** and why (and the Connection constraint if §1 flagged it)
- **Data model**: the tables and files it will store
- **Routes / pages**: what the user can actually open and do
- **Audience**: members-only at registration, and the audience it is meant
  to be widened to later, if any
- **Access model**: who can see what, and who can edit, decided per request
  for each kind of caller contract R3 names (`get_app_contract`
  with `sections: ["R3"]`). For an identity-aware app a member is only one
  of them: never design as if
  every caller is one, and give per-person data and roles only to a caller
  with an identity. The platform manages only membership:
  `X-Forwarded-Groups` carries at most this app's own members group, and
  only for a member (the `App groups:` line of the status you read in the
  Version gate, with the app's name in place of `{app}`). Any finer role (an editor, an
  admin view) needs the app's own role table keyed on `X-Forwarded-Subject`,
  the person's identity provider ID, never on the email address, which can
  change for one person and pass to another; key per-person data on it too,
  and do not design around reading other groups from the header. The
  header rule is `inno-platform-conventions`' **Identity** section. For an
  anonymous app every caller is anonymous, at every audience: the design
  has no per-person data, roles or views at all (R10).
- **Accessibility** (a browser app): who will use it, the main flows
  a person has to complete, and how each one works from the keyboard alone
  and with a screen reader. For an MCP app, say it does not apply.
- **Deployment pattern and stack**
- **Name** (confirmed available via `check_name`) and the exact hostname it
  produces
- **Initial members**, if any

Only after that design is in your reply: **stop and get explicit user
approval** (of the design *and* the name) before §2. Ask the approval question
in your own words referencing the design the user can now read; put genuinely
separate decisions (name choice, identity, deployment type, members) in their own
questions rather than folding them into the approval. Registration provisions
real resources (a database, file storage and the app's member list) and
binds them to the user's repo; the type and the identity are fixed at
registration.

The type, the identity and the design seed the scaffolding in §4.

## 2. Create the repo from the template

The repo must land in the **user's own** ownership: the platform has no
create-on-behalf path and never creates a repo itself. That constrains *whose
account* it lands in, not *who runs the command*.

**Preferred: do it for them with `gh`.** Run `gh auth status`; an authenticated
account with `repo` scope is the user's **own** credential, so a repo it creates
lands in their ownership exactly as the browser path does. Confirm the name and
visibility with them, then:

```sh
gh repo create {owner}/{repo} --template <template repo> --private
```

Here `<template repo>` is the owner/name on the `Template repo:` line of the
status you read in the Version gate.

- Suggest the app name itself; public or private is fine. Ask which they want, or run
  `gh repo list --limit 5 --json name,isPrivate` and match what their recent repos use, rather than
  assuming.
- Template copying is **asynchronous**: an immediate `git clone` can land an
  empty repo. Poll `git fetch` until `origin/main` exists before checking out.

**Fallback: walk them through the browser** when `gh` is absent or
unauthenticated, the account it holds is not theirs, or they simply prefer it:

1. Open the `new repo:` link on the `Template repo:` line of the status you
   read in the Version gate (it ends in `/generate`). It is GitHub's
   "Use this template" page for the instance's public template repo. (You can also reach
   it from the template repo's green **"Use this template" → "Create a new
   repository"** button.)
2. Set the **owner** to their own account or org, and the **repository name** to
   their choice (suggest the app name itself). Public or private is fine.
3. Click **Create repository**. The repo lands in **their** ownership, already
   scaffolded from the template.

Note the resulting `owner/repo` slug: that's the `repo` argument for
`register_app`.

## 3. Register the app (two calls)

`register_app` is a **two-step** flow with two things in between: committing a
proof-of-control file to the repo, and the App install. Call it, commit the
proof file it names, give the user the install link, wait for them to install,
then call it again.

### Call 1: start registration, commit the proof file, get the install link

```
register_app({ app, repo, description, type, identity, members, accept_guardrails: true, connections })
```

- `app`: the app name from §1 (drives the hostname). The wire parameter is
  `app`; no tool names the target app `name` (a variable's name is `name`
  inside `set_app_variables`' `variables`, and `remove_app_variables` takes
  `names`).
- `repo`: the `owner/repo` slug from §2 (a **slug, not a URL**). `app` and
  `repo` are the only two the schema requires; everything below is optional to
  the schema, though the handler still refuses the call without
  `accept_guardrails: true`.
- `type`: from the design decision (§1b): `"function"` for the greenfield
  default, `"container"` when the description warranted it, `"mcp-function"` for
  an MCP server, `"mcp-container"` for an MCP server that needs the container
  shape. Omit for container. The type is fixed at registration and can't be
  switched later (register a new app to change it). Call 2 may leave `type`
  and `description` out: the first call's are used (`register_app`'s
  description says so), and a call 2 that names another keeps the first
  call's, saying so on a `WARNING:` line for the type and a `NOTE:` line
  for the description (a description call 1 left out takes call 2's). A
  repeated call 1 changes either only while the platform still answers it
  as call 1 (`Registration started`, with the install link), which is only
  until the platform GitHub App covers the repo: from then on a repeat
  checks the proof file (`repo_control_unproven`, changing nothing, while
  it is missing) and, once it finds it, runs as call 2 and creates the app
  with the first call's type, fixed for good. So settle the type
  before call 1 when the App already covers the repo, and otherwise before
  the user installs it (`get_platform_docs`' **What the tools do in
  detail**, its Registration item, has the rule).
- `identity`: from the design's identity question (§1b): `"anonymous"`
  when the app must not know who each caller is; omit it, or pass
  `"identity-aware"`, otherwise. The app's identity is set by the call
  that creates the app (call 2) and never changes: a call that resumes or
  repeats a registration keeps the identity the app already has, and call
  2's answer names it on its `Identity:` line. Unlike the type, call 1
  does not record it, so pass the same `identity` on both calls, call 2
  above all, and check that line.
- `accept_guardrails: true`: required; you must have done the §1a review.
- `members` is an optional list of the addresses people sign in with (at
  most 50). Each address is
  added to the app's member list at once, and is notified that the app was
  shared with them (in-platform plus email per their own notification
  settings) when the app's first deploy completes, once its address answers,
  not at registration; call 2's answer says so. Name only people who should
  hear about it when it goes live. An address the identity provider does
  not know is still added but not notified, and call 2's answer names it on a
  `WARNING:` line of its own. Check its spelling with the user, and if it
  is mistyped, remove it with `revoke_access` (`inno-manage-app`). An address the
  platform could not check with the identity provider is added too, with its
  own warning. Each
  added address is pinned to an account as `grant_access` pins it
  (`inno-manage-app`), and the owner's own row to the account that registers
  the app (when a platform admin resumes someone else's registration, the
  owner's row waits for that owner's first sign-in instead). A member whose
  address resolves to an account the list already holds under another
  address (such as the owner's own alias) gets no second row and is not
  notified, and the answer names it on a `WARNING:` line too.

  On a platform that lists allowed email domains, an address outside them
  refuses the whole call with `email_domain_not_allowed` before anything is
  created. That includes the user's own address, because the caller becomes
  the app's owner (**Reading register_app's responses** below says what to
  tell them).
- `connections`: optional list of names, when §1 step 5 flagged a per-user
  backend. Pass what you plan to set up; it **creates nothing** (only
  `set_app_connection` can) and, for an identity-aware `mcp-container`, is
  echoed back in the response as a reminder to configure each one; any other
  type's answer says the app takes no Connections (`set_app_connection`
  refuses it `app_type_unsupported`), the sign that the type is wrong for a
  per-user backend (§1b's `mcp-function` constraint). A badly-shaped name is noted in the response and
  never fails the registration. The schema bounds the list (at most 16
  names, each at most 64 characters); add any beyond that afterwards with
  `set_app_connection`. An anonymous app takes none: a call with
  `identity: "anonymous"` and any `connections` is refused.

The first call returns text beginning **`Registration started for "{name}" ←
{repo}.`** It carries, in this order: (a) the template link again, in case the
repo doesn't exist yet; (b) a **proof-of-control file**: a `path:` under
`.inno-platform/` and the exact `contents:` (a 64-character hex string), with a
sample command; and (c) an **App install link**
(`https://github.com/apps/…/installations/new?state=…`).

**Commit the proof file first.** Installing the GitHub App proves the platform
can SEE the repo; this file proves the caller can CHANGE it, and nothing binds
until it checks out. Use the path and contents exactly as the response prints
them; never derive or shorten them. Commit it on the repository's **default
branch** (`main` for a template copy) and push:

```bash
git clone <the user's repo>   # skip if §2 already cloned it
cd <repo>
git fetch origin && git checkout main && git pull --ff-only   # fails until the template copy has landed: wait and retry
mkdir -p .inno-platform
printf '%s\n' '<contents from the response>' > '<path from the response>'
git add '<path from the response>'
git commit -m "platform registration proof"
git push origin HEAD
```

This is not a user-only step: do it with the user's own authenticated `git` or
`gh`. Only when you have no write credential for the repo, walk the user through
GitHub's web UI (**Add file** > **Create new file**, the exact path as the file
name, the exact contents, committed directly to the default branch).
Surrounding whitespace (such as the newline `printf` adds) is tolerated;
everything else must match exactly. Leave the file in place: call 2 re-checks it
immediately before provisioning. After that nothing reads it again, and keeping
it is harmless. The push may start a CI run in the repo; it deploys nothing (the
app isn't built yet), so there is nothing to act on in its result. Never commit
the proof on an empty clone (template copying is asynchronous, so
`git checkout main` fails until `origin/main` exists) and never force-push it:
a forced push over the template copy wipes the scaffold, and call 2 then has
nothing to prune.

**Then give the user the install link verbatim** and ask them to:

1. Open it, and **install the platform GitHub App** on the account/org that owns
   `repo`, granting it access to that repository (repo-only access is fine; they
   can scope it to just this repo). If the App is already installed there with
   access to this repo (including "All repositories"), they can skip the link:
   call 2 verifies access directly.
2. Save the configuration. GitHub redirects them to the platform's verification
   page, which says **Repository verified** once the App can reach the repo AND
   the proof file matches. If it says **Proof file not found**, the file is
   missing, on the wrong branch, or has the wrong contents: fix it, then reopen
   the link or simply run call 2 (it re-checks without the redirect). If it
   says **GitHub App installed** instead (GitHub's configure flow, for an
   account that already had the App), that page carries no registration: just
   run call 2.

The link expires in 24 hours. Re-running `register_app` while the registration
is still pending reuses it, with the same proof path; once it has expired, the
response names a NEW proof path, and that new file is the one to commit.

### Call 2: finish provisioning, get the deploy.yml

Once the proof file is pushed to the default branch AND the user confirms
they've installed the App (or the App already covered the repo), call
`register_app` **again with the same arguments** (`type` and `description`
may be left out, as above; `identity` may not). This re-checks the proof file,
then finishes the job server-side: it prunes the template scaffold to the
chosen type in a new commit on the repo's default branch (for an anonymous
app, laying the template's anonymous layer for that type over the root in
the same commit: its guide, and reference code that reads no identity),
provisions the app, and binds the repo. It returns text beginning
**`App "{name}" registered from {repo}`** and containing:

- On that first line, the deploy-by time:
  `Deploy it by <date> <time> UTC`, with what happens if the first deploy
  has not completed by then and when the reminder comes, and, when the call
  named members, that they are told when the app first deploys. Keep both
  for the hand-off (§5). The date comes only on the call that provisions an
  app that is not pinned: a pinned app's answer has none, and neither has a
  repeat of a registration already provisioned (nor its members sentence).
  Then read the deadline from `app_status`'s `Lifecycle:` line, which says
  plainly when an app is pinned.
- `URL (after first deploy): https://<app host>`: **quote
  this from the response, never construct it** (the host and domain are
  the instance's). For an **mcp-function** or **mcp-container** app the
  response surfaces the **MCP endpoint** (`…/mcp`) instead; same rule: quote
  it from the response. Until the first `inno-ship` starts its deploy the
  address serves no app: from platform v0.17.9 it shows a page saying the
  app has not been deployed yet (while that deploy runs, a page saying the
  app is not available right now).
- `Identity: <identity-aware or anonymous>`: the identity the app was
  created with, which never changes. If it is not the one the design chose,
  stop and tell the user before building: a different identity is a new
  app.
- A `.github/workflows/deploy.yml`: the thin caller workflow that wires the
  repo to the platform's reusable CI. **Overwrite the repo's copy with the
  snippet the response returned** (an older template may still carry one). The template ships no `deploy.yml`: this file
  always comes from `register_app`'s second call. It carries the explicit
  `with: app: {name}` input and is correct for any repo name, so write it in
  every case. This is a real step, not a hands-off one. Keep the
  `workflow_dispatch` trigger (the platform re-dispatches it for security
  respins). The snippet has no `secrets:` line, and the file must not gain one:
  `secrets: inherit` is a blocking finding for the `sast` gate, and the
  platform workflow needs no caller secrets.

### Reading register_app's responses: branch, don't assume

`register_app`'s description states what each refusal means. What to do next:

- **`Registration started …`** on call 1: commit the proof file, hand over the
  install link, and wait (above). The same text on call 2 means the platform
  still cannot see the repo through the App (not installed yet, installed
  without access to this repo, or a transient GitHub failure), or the 24-hour
  registration expired. Compare the proof `path:` with the one you committed:
  if it changed, commit the new file. Then have the user install the App on the
  repo (or widen its repository access) and call again.
- **`App "{name}" registered …`**: call 2 succeeded; proceed to §4.
- **`guardrails_not_accepted`**: do the §1a review, then pass
  `accept_guardrails: true`.
- **`invalid_name` / reserved**: pick another name (you should have caught
  this with `check_name`).
- **`name_unavailable`**: an app with that name already exists and is not the
  caller's own partial registration; pick another name.
- **`app_anonymous`**: the call named `identity: "anonymous"` and some
  `connections`. An anonymous app has no Connections, since it is never told
  who its caller is. Drop `connections`, or, if the app really must reach a
  backend as each person, go back to the design: that app is identity-aware.
- **`invalid_repo`**: pass an `owner/repo` slug, not a URL or a bare name.
- **`repo_control_unproven`**: the error text repeats the exact path and
  contents: commit that file (call 1 above) and call again. It can come back
  at call 2 even after the setup page said verified, because call 2 re-checks
  the file right before provisioning, so never delete it early.
- **`name_quarantined`**: the name is held after a purge until the UTC time
  the message names, and past it while a `function` or `mcp-function` app
  that read the purged app's data has not been rebuilt or redeployed since
  (the message says so), with no admin bypass of the date: pick another name
  (check it with `check_name`), or wait until the hold ends, which that
  app's rebuild or redeploy brings about for the second part. A purge of an
  app that never completed a deploy has no dated hold, so only the second
  part can apply to it.
- **`repo_unreachable`**: have the user reinstall the App on the repo, then
  call again.
- **`repo_identity_changed`**: confirm the repo's current `owner/repo` slug
  with the user and call again with it; a new slug starts a fresh
  registration with a new proof file and a new install link (have the user
  open that link and save). The very next call starts clean: there is no
  window to wait out.
- **`invalid_member_email`**: one of `members` is not a plain email address.
  Fix or drop it and call again.
- **`email_domain_not_allowed`**: the message names the address and the
  domains. Either call can answer it, and nothing was created.
  - **An address in `members`**: fix or drop that address and call again.
  - **The user's own address** (this holds even for a call that repeats a
    registration they already finished, which then hands back no
    `deploy.yml`): nothing on their side fixes it. The list is the instance
    manifest's `identity.allowedEmailDomains`, which only the platform's
    operator can change, by editing the manifest and redeploying. Tell the
    user plainly that their address cannot own an app on this platform, and
    stop.
- **`host_in_use`**: nothing was created. Choose another name, or have the
  record removed if it is unused.
- **`host_check_failed`**: nothing was created. When the message says the
  platform's own access to its DNS is missing, this is not the user's to
  fix: tell them to ask a platform admin, whom the message names (with the
  platform's support contact when it has one). When it says the read
  failed, try again shortly.
- **`upstream_error`** from call 2's re-check of the repository: read its
  message and act on it as `inno-platform-conventions`' **Refusals every
  tool shares** says.
- **More than 50 `members`**: the tool's schema refuses the list before the
  tool runs, with an argument-validation error on `members`. Register with a
  shorter list and add the rest afterward with `grant_access`.
- **`app_limit_reached`**: the user is at their active-app limit; resolve per
  §1 (the user chooses to stop one of their own apps, or an admin raises the
  limit; never propose which to stop).
- **`repo_already_registered`**: that GitHub repo is already bound to an app
  (one repo binds to at most one app). Use a different repo, or manage the
  existing app via `inno-manage-app`. (`repo_id_conflict` is the audit action
  the platform records for this refusal; callers never see it as an error code.)
- **`repo_owner_claimed`**: the message names who holds that GitHub account:
  ask them or a platform admin to register on the user's behalf, or use a
  repo under an account of the user's own. Platform admins bypass this check,
  so an admin can register under a shared-org account directly without going
  through the first user.
- **`repo_mismatch`**: a partially-finished registration exists for this name
  with a *different* repo. Finish it with the original repo. To start over
  instead, stop that app (`stop_app`, `inno-manage-app`), have a platform
  admin purge it (`purge_app`), and register again (the purge of an app
  that never completed a deploy frees its name at once, unless another app
  still holds a deployed data link to it), or under another name.
- **`app_exists`**, **`provision_in_progress`**, **`app_not_registered`**,
  **`repo_not_provisioned`** or **`scaffold_not_provisioned`**: another call
  on the same name raced this one. `app_exists` means the other call
  registered it (`check_name` says whose it is now); `provision_in_progress`
  means it is provisioning it, so call again in a moment; the other three
  mean the app's record changed under this call, so call again.
- **`github_app_not_configured`**: the platform's GitHub App isn't set up on
  this deployment; nobody can register until an admin configures it.
- **`github_app_key_invalid`** or **`github_app_unavailable`** (on a call
  that makes the install link): a fault in the platform's GitHub App, which
  only a platform admin can fix. Tell the user it is not theirs to fix, and
  stop until an admin has.
- **Repo wasn't template-derived.** The user registered a repo that didn't
  come from §2's "Use this template" flow (a blank GitHub "New repository" is
  the common way this happens). Two cases:
  - **No `scaffold/` at all.** Call 2 leaves the repo untouched and says
    nothing about it, for every type. The cue: after call 2 finishes, the
    repo shows none of the type-specific files described in §4. This is not
    an error to retry. Treat it as the empty-repo path in §4 below.
  - **`scaffold/` with no overlay for the type** (a `function`,
    `mcp-function` or `mcp-container` registration). The repo came from a
    template copy older than that type, and call 2's answer warns, naming
    `scaffold/` and the missing `<type>/` overlay. Call 2 wrote nothing to
    the repo, but it has bound the app to it and provisioned it, and every
    deploy finds the app by this repo's id. So bring this repo up to the
    current template in place, never by creating a new repo (a new one is
    not bound to the app): lay the type's files out from a current copy of
    the template repo (`references/hand-authored-layout.md`), and delete
    `scaffold/` before deploying, since the leftover fails the first
    deploy's `config-integrity` gate.
  - **`scaffold not applied`** (a warning): the platform could not write
    the prune commit, so the repo is as it was. Lay the type's files out
    the same way (a template copy already holds them under
    `scaffold/<type>/`) and delete `scaffold/` before deploying.
- **`registration_disabled`**: a platform admin must re-enable self-service
  registration (`registration.enabled`).
- Any other non-empty error: surface it verbatim rather than retrying
  blindly. The refusals any platform tool can give are explained once, in
  `inno-platform-conventions`' **Refusals every tool shares** section.

## 4. Pull and scaffold

You cloned the repo in §3 to commit the proof file. Call 2 then pushed the
platform's scaffold prune to the repo's default branch as a new commit from
the server side, so bring the clone up to date before touching anything (a
push from the stale clone would be rejected as non-fast-forward):

```bash
cd <repo>
git pull --ff-only   # picks up the registration's "scaffold: <type>" (or "scaffold: <type>, anonymous") commit, if it applied one
```

If the proof file was committed through GitHub's web UI instead, clone now:
`git clone <the user's repo>` (e.g. `git@github.com:<owner>/<repo>.git`), then
`cd <repo>`.

After call 2, the repo has been **pruned to the deployment type you chose**:
the template carries every scaffold and the platform rewrote the repo at
registration. No type ships `.github/workflows/deploy.yml`: you write it
from call 2's snippet per §3. A
**function** repo has the TS reference (`app/index.ts` and the identity
helper `app/identity.ts`, and no `app/package.json` until you add a
dependency), an **mcp-function** repo the MCP-server TS reference (also
`app/index.ts` and `app/identity.ts`, plus `app/package.json` and
`app/package-lock.json`), and
a **container** repo the Python/Starlette reference (`app/`, incl. `main.py`,
`storage.py`, `templates/`, `requirements.txt`, plus `Dockerfile` and `lib/`).
An app registered `anonymous` has no `app/identity.ts` in either function
type. **List the files before you read them** (for example `git ls-files`)
and read only the ones that are there: one command that names a file the
type does not ship fails as a whole, and the user sees "Failed" on a step
that went fine.
An **mcp-container** repo ships **its own overlay** (`scaffold/mcp-container/`):
a stateless FastMCP starter for `app/main.py`, plus its own `README.md`,
`CLAUDE.md`, and `app/requirements.txt`, applied over the container root
(see the bullet below); `Dockerfile`, `lib/`, and `app/storage.py` stay as
the container reference's. The platform owns a fixed set of other paths (a
repo-root `src/`, the root build files, any wrangler config, and the rest
contract R7 lists: `get_app_contract` with `sections: ["R7"]`), and none of
them may be in the repo: don't create any. `get_platform_docs`'
**Environment & config integrity** section lists them too; the plugin's
copy, with what to do when a migrated repo already carries one, is
`inno-platform-conventions`' **Files you must not touch** section. Load
that skill before writing any application code (stack policy, storage,
identity, the do-not-touch file list), and, for a container or
mcp-container app, the `inno-containerize` skill before editing the
Dockerfile.

**The empty-repo path: if the repo wasn't template-derived, there's nothing
to prune, so author the layout by hand.** A repo created via GitHub's blank
"New repository" flow (instead of §2's "Use this template") arrives with no
scaffold, so call 2 leaves it as-is. Recognize this early: the repo is
missing the type-specific files described above. Then read
`references/hand-authored-layout.md`, which says what to copy from the
template repo for each type (and, for an anonymous app, its anonymous
layer) and which `CLAUDE.md` to start from, and write
`.github/workflows/deploy.yml` from call 2's response.

**An anonymous app gets its own guide and reference code.** For an app
registered `anonymous`, call 2's scaffold commit (`scaffold: <type>,
anonymous`) also laid the template's `scaffold/anonymous/<type>/` over the
root: the repo's `CLAUDE.md` is the anonymous guide for its type, its entry
files are reference code that reads no identity (a page with no `/me` route
and no sign-out footer, or an MCP server with no `whoami` tool), and a
function-shaped repo carries no `app/identity.ts`, which the layer's own
`.scaffold-remove` deleted. That guide, not the identity notes in the type
bullets below, is the rule for this app: it reads no identity header and
shows no sign-out link (it never shows who is signed in, so R4 asks for
none); a container repo's storage client still carries the identity
helper, which this app never calls; and it follows R10 (`get_app_contract`
with `sections: ["R10"]`), its cookie rule and the uploaded-file rule
(`inno-platform-conventions`' **An anonymous app: R10** and **Files someone
uploaded**). Two older template copies show here:

- call 2 warned that no `scaffold/anonymous/<type>/` guide was found: the
  template copy has no anonymous layer, and the repo carries the
  identity-aware guide and entry files. Copy the files of
  `scaffold/anonymous/<type>/` from the current template repo (the
  `Template repo:` line) over the repo's root before building, then delete
  the paths its `.scaffold-remove` lists and that file itself, as the
  warning says and the platform's scaffold commit would have;
- the guide is the anonymous one but the entry files still read identity (a
  function-shaped repo still has `app/identity.ts`, or the entry file still
  has a `/me` route, a sign-out footer or a `whoami` tool): the template
  copy is older than the layer's reference code. Take the layer's entry
  files from the current template repo the same way, or remove that helper
  and those reads as you build.

**Scaffold by the deployment type you chose in §1b.** The contract sections
you read in §1b (§1.1 to §1.3) are the authority for each type's deltas.

- **`function` app (greenfield default):** the entry is **`app/index.ts`**
  exporting `export default { fetch(request, env, ctx) }`; extend it rather
  than re-scaffolding. Read the caller with `currentUser(request.headers)`
  from the scaffold's `app/identity.ts`, handling no user (`null`) first in
  each route that needs a person, never defaulting it into a value, and
  keying per-person data on its `subject` (`inno-platform-conventions`'
  **Identity** section), serve **`GET /healthz` as a
  route** returning **exactly 200** (a 204 or a redirect to `/healthz/` fails
  both the CI smoke gate and the runtime probe), and reach storage through
  the app's **own bindings** `env.DATA` (D1) and `env.FILES` (R2), not
  `storage.internal`. Declare every npm package the code imports in a
  **non-root** `app/package.json`, and commit the `app/package-lock.json`
  that `npm install` (run inside `app/`) produces, kept in sync with
  `package.json`. The install rule and everything it refuses have one home,
  `inno-platform-conventions`' **Node apps** paragraph; the short of it is
  that a runtime import must sit under `dependencies`, because CI installs
  `--omit=dev`. Never interpolate user data into hand-built HTML: even
  escaped, the SAST gate blocks it; return dynamic data as JSON (like the
  scaffold's `/me`) or use an auto-escaping template library. Do NOT create
  `wrangler.jsonc`/`app-worker.jsonc`: those are platform-injected. The
  scaffold's page already carries the **sign-out link** (R4), a plain link
  to `/_auth/signout` shown only when `currentUser` returns a user: keep that
  rule wherever the app shows who is signed in (`inno-platform-conventions`'
  **Sign out** section).
- **`mcp-function` app:** everything in the function bullet applies except
  the sign-out link (there is no browser session); the scaffold ships both
  `app/package.json` and its lockfile. Serve MCP at `POST /mcp` with the MCP
  TypeScript SDK's `WebStandardStreamableHTTPServerTransport`, constructed
  **without a `sessionIdGenerator`** (stateless), and implement **no auth of
  any kind**: never route `/.well-known/oauth-protected-resource` yourself
  (§1.2 says why). The app refuses inside MCP (a tool result marked as an
  error, or a JSON-RPC error), never with an HTTP status: a MUST of §1.2.
- **`container` app, tested stack (Python):** start from the reference app
  (`app/main.py` + `Dockerfile`) and extend it; don't regenerate from scratch.
  Read the caller with `current_user(request)` from `app/storage.py`,
  handling no user (`None`) first in each route that needs a person, and
  key per-person data on its `subject`. The reference page already shows the
  sign-out link only when the helper returns a user (R4).
- **`container` app, another stack:** replace `app/` and the `Dockerfile`
  wholesale for that stack, honoring the contract (port 8080, `/healthz`,
  identity headers, the `storage.internal` endpoints, and a sign-out link
  wherever the app shows who is signed in). A JS or TS container reads the
  caller with `currentUser` from `lib/storage.js`; any other stack reads the
  headers by the same contract, an empty or missing `X-Forwarded-User` being
  no user and `X-Forwarded-Subject` the key for per-person data.
- **`mcp-container` app:** pruning applied the template's
  `scaffold/mcp-container/` overlay: its `.scaffold-remove` deleted
  `app/templates/` (this type has no use for it), and its `app/main.py`,
  `README.md`, `CLAUDE.md`, and `app/requirements.txt` replaced the container
  root's; `Dockerfile`, `lib/`, and `app/storage.py` stay as the container
  reference's. `app/main.py` already speaks Streamable HTTP at `POST /mcp`
  with two example tools (`whoami`, `echo`) and already answers non-POST
  `/mcp` requests with 405: extend it rather than adapting a Starlette demo
  into an MCP server, and keep it stateless (§1.3). `app/storage.py`
  carries the storage **and `Connections` helpers** your tools consume (see
  `inno-add-connection`).
  Identity is §1.2's: implement no auth of your own, read the caller with
  `current_user(ctx.request_context.request)` from `app/storage.py` (as
  `whoami` does), handling no user first and keying per-person data on its
  `subject`, never route `/.well-known/oauth-protected-resource` or a path
  under `/_auth/` yourself, and add no sign-out link.
  The app refuses inside MCP (a tool result marked as an error, or a
  JSON-RPC error), never with an HTTP status: a MUST of §1.3.
  **Keep the starter's `transport_security` setting**, which
  `get_app_contract` §1.3 states and explains; changing it breaks every
  `/mcp` request the front door forwards. The starter pins FastMCP below `mcp` 2 in
  `app/requirements.txt` (2 renamed the `FastMCP` API the starter uses);
  build the container image per `inno-containerize`.

**Delete the scaffold marker as you build.** The template repo ships
`app/.needs-build`, which makes CI skip deployment until it's removed. Once you
begin writing the real app (per the approved design), delete it:

```bash
rm -f app/.needs-build
```

Leaving it in place means `inno-ship` will refuse to deploy, by design.

Typical scaffolding steps for a new feature (Python **container** reference
shown; a **function** app does the equivalent inside `app/index.ts`'s `fetch`
handler: route on the URL, read the caller with the identity helper and
handle no user first in each route that needs a person, read/write
`env.DATA`/`env.FILES`):
- Add routes to `app/main.py` (container) or `app/index.ts` (function); split into
  modules under `app/` as it grows.
- (Container, Python) add templates under `app/templates/`; never delete the
  directory while the reference Dockerfile is in use (a missing `templates/` is
  a common runtime 500, see `inno-containerize`).
- Add pinned dependencies to the stack's manifest (`app/requirements.txt` for
  the Python container; `app/package.json` for a function or a Node container).
  For a function or mcp-function app, also run `npm install` inside `app/` and
  commit the updated `app/package-lock.json` in the same commit (see the
  function bullet above).

**Browser apps (`container`, `function`): accessible pages and
response headers from the first commit.** Scaffold every page with
`<html lang>`, a real `<title>`, a visible label on each form control, and
visible focus styles, and add one middleware that sets the response headers
`get_app_security` §9 lists, with the starting Content-Security-Policy it
gives for the deployment pattern you chose. For an SPA, also handle route
changes: update `document.title` and move focus to the new view. The detail
lives in the served notes (`get_app_accessibility`, `get_app_security` §9);
take it from there, not from this list. The plugin's summary of both is
`inno-platform-conventions`' **Accessibility** section and **Response
headers** paragraph.

**Container apps: the storage endpoints cap request bodies.** Contract R5
(fetch `get_app_contract` with `sections: ["R5"]`) gives the SQL body cap, the
file `PUT` cap, and the refusal of a `PUT` with no `Content-Length`. So a
route that writes in bulk sends batches, and an upload route checks the size
itself, with its own message, and sends the body with its length. The codes
and the reasoning are
`inno-platform-conventions`' **Persistence** section. A function app reaches
`env.DATA`/`env.FILES` directly and has neither cap.

**Rewrite `README.md`: this is required, not optional.** The template's README
is the template's own ("Use this template…", template internals) and describes
nothing about this app. Replace it with a **high-level overview of the user's
app**: what it does, who it's for, and the app's URL. Keep it short (a few
paragraphs is right); the platform mechanics (identity, storage, CI) already live
in `CLAUDE.md` and don't belong here. The README is the user's file from then
on: they can deepen it to whatever level of detail they prefer, and later
features should keep it truthful.

## 5. Hand off

Once scaffolding is in place, tell the user the app was registered (their repo +
future URL; for an **mcp-function** or **mcp-container** app, the `/mcp`
endpoint their MCP client will use), and that the next steps are: write the
app, run
`inno-safety-preflight` (it pushes to the default branch, which runs the real
gates and deploys nothing), then `inno-ship`. Beyond the registration
proof file (§3), don't push anything yet unless asked: `inno-new-app`'s job is
registration + scaffolding, not deploying.

Tell them the deadline too, with the date and time quoted from call 2's
answer (`Deploy it by <date> <time> UTC`), never worked out from memory: an
app whose first deploy has not completed by then is deleted (its repository
is never touched), a reminder (`first_deploy_due`) comes the number of days before it
that the answer gives, and its name is then free again at once, unless
another app still holds a deployed data link to it. When the answer gives
no date (a pinned app, or a repeat of a registration already provisioned),
read the deadline from `app_status`'s `Lifecycle:` line; only that line
says an app is pinned. When the registration named
members, say they are told when the app first deploys, not now. Point them
at the platform's user guide too: the `Panel URL:` address with `/guide`
after it, readable by anyone signed in to the platform.

Tell the user the app is members-only for now. When the design means it
for a wider audience (internal, or public for an anonymous app), that
widening comes after `inno-ship`, through `inno-manage-app`'s widening
review; `inno-ship` hands over to it. For a two-app design, register the
second app the same way, and follow `references/two-app-pattern.md` for the
order.

If §1 flagged that the app needs to reach another service as each person using
it, do that setup now, before writing the rest of the app: run the
`inno-add-connection` skill (requires the `mcp-container` type and an
identity-aware app, from §1b).

If the app needs an app-level key or config value instead (one API key the
whole app shares, a base URL), set it after registration with
`set_app_variables`: it reaches the app as a plain environment variable.
Never put it in the repo; gitleaks fails the build on the full history. A
route that spends an app-level key needs the limits `get_app_security` §5
sets, per client and globally.

If the app will read platform Variables, consider declaring them in
`app/inno-variables.json` (contract §2.3 gives the format) so an owner
without your source can see what it needs (see `inno-platform-conventions`).
