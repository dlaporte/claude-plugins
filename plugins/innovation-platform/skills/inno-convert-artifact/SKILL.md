---
name: inno-convert-artifact
description: Use when the user wants a Claude artifact (made in claude.ai or Claude Desktop) turned into an app on the Innovation Platform ("I made an artifact called X that does Y, put it on the platform", "convert this artifact into an app", "deploy my artifact"). Rebuilds the artifact as a function app whose browser interface the platform's CI builds from app/ui/, swaps the artifact's window.storage for the app's own database, adds sign-out, then registers, preflights and ships it.
---

# inno-convert-artifact

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

A Claude artifact is a single page (React, or plain HTML) that runs inside
claude.ai, with libraries and a saved-data API (`window.storage`) that
claude.ai provides. This skill turns one into a **function** app: a Cloudflare
Worker that serves the artifact's page, with the page built by the platform's
CI from `app/ui/` (the contract's **Browser interface**, section 1.1), and the
artifact's saved data kept in the app's own D1 database. The artifact's look
and behavior carry over; what changes is where its code is built, where its
data lives, and who can reach it (the platform's front door, not a claude.ai
share link).

**After conversion, the repository is the source of truth.** Say so to the
user up front: further edits to the original artifact on claude.ai do not
reach the app, and changes are made in the repository from then on.

Requires the `inno-platform` MCP server (ships with this plugin). The first tool
call triggers a browser sign-in through your organization's identity
provider: expected, not an error.

**Asking a platform admin.** Where this skill sends the user to a platform
admin, the request goes to the contact the platform names: the `Support:`
line of the status you read in the Version gate, when it has one.
`inno-manage-app`'s **Asking a platform admin** is the one home for that
rule.

## 1. Check the platform builds browser interfaces

Call `get_app_contract` with `sections: ["1.1"]`. If the section has no
**Browser interface (optional)** bullet, this platform release cannot build
an artifact's interface: say so, ask the user's platform admin to upgrade
the platform, and STOP. Do not work around it by committing a pre-built
page: CI removes `app/.ui-build/` and would not audit or scan a bundle built
elsewhere.

Read that bullet in full: it is the authority on where the entry lives, what
is built, and what the generated module exports. Fetch `"R3"`, `"R4"` and
`"R5"` beside it, and call `get_app_security` and `get_app_accessibility`:
all three are checklists for steps 4 and 6.

## 2. Get the artifact's source

The artifact lives in a claude.ai conversation, not on disk. Take it, in this
order of preference:

1. **A file.** The user downloads it from claude.ai (the artifact's menu has
   a download or copy option) and gives you the path.
2. **Pasted code.** The user copies the artifact's code into the chat.
3. **A link.** If the user gives a claude.ai artifact link and this client
   has a tool that reads one, read it with that tool. If not, ask for the
   file or the code instead. Never fetch a claude.ai page with a generic web
   fetch: it needs the user's own sign-in.

Ask the user, in their words, what the artifact does and who should use it.
That answer is the app's description at registration and the purpose the
guardrails review judges.

## 3. Take inventory

Read the whole artifact and list, using `references/artifact-runtime.md`:

- **Kind**: React (a component with a default export, usually `.jsx`/`.tsx`)
  or HTML (a full page with `<script>` blocks).
- **Libraries**: every import (React) or CDN `<script>`/`<link>` tag (HTML),
  each mapped through `references/libraries.md` to an npm package and a
  pinned version.
- **Saved data**: every `window.storage` call, and whether it passes `true`
  as its last argument (shared) or not (personal).
- **Calls to Claude**: any `window.claude.complete` (or other `window.claude`)
  call. **Not supported in this version of the skill**: the platform forbids
  an endpoint that relays a browser-written prompt on the app's key
  (`get_app_security` section 11), and who pays for model calls is a policy
  decision this skill does not make. List each use and what the feature
  does; the plan removes it (step 4).
- **Outside requests**: any `fetch` to another site, which the page's
  Content-Security-Policy (`connect-src 'self'`) blocks. Each needs a
  server-side route in `app/index.ts` with a fixed host list (`get_app_security`
  section 10), or it is dropped.
- **File inputs and downloads**, and anything that renders user text as HTML
  (`dangerouslySetInnerHTML`, `innerHTML`): the second is a finding to fix.
- **Browser storage**: `localStorage`/`sessionStorage` keep working, per
  browser; say so, and suggest `window.storage` for anything that should
  follow the person.

## 4. Present the plan, then ask for approval

Run the **guardrails** review first: call `get_guardrails` and judge the
artifact's purpose and behavior against it. A conflict is a HARD STOP:
`register_app` requires `accept_guardrails: true`, which you must not pass
until it is clean or the user has an explicit admin exception.

Choose the app name with `check_name`, following `inno-new-app` section 1's
name bullet unchanged.

Then write the plan **into your reply**, never only inside an approval
prompt:

- **What carries over**: the interface, unchanged in look and behavior.
- **Libraries**: each with its npm package and pinned version.
- **Saved data**: which keys are personal (each signed-in person's own) and
  which shared (one copy for everyone who reaches the app), and that data
  saved in the artifact on claude.ai does not move over.
- **What is removed or changed**: every `window.claude` feature (and that it
  can come back once the platform settles model calls), every outside
  request without a server-side route, every unsafe HTML render.
- **Who can reach it**: identity-aware and members-only to start; the
  audience it is meant for in the end (internal, everyone who signs in, is
  the usual answer for a team tool), reached later through
  `inno-manage-app`'s widening review. A converted artifact is
  identity-aware: its saved data is keyed on who is signed in.
- **The app name** (checked) and that the repository becomes the source of
  truth.

Get explicit approval of the plan and the name before step 5.

## 5. Create the repository and register

Follow `inno-new-app` sections 2 and 3 unchanged, with these answers: type
`function`, identity `identity-aware`, the approved name, and the user's
description. That creates the repository from the platform's template in the
user's own account, commits the proof file, has the user install the
platform GitHub App, and returns the `deploy.yml` to write. Then pull, as
`inno-new-app` section 4 says: the registration's scaffold commit leaves
`app/index.ts`, `app/identity.ts` and the function `CLAUDE.md`.

## 6. Build the app from the starter

The starter is `${CLAUDE_PLUGIN_ROOT}/skills/inno-convert-artifact/assets/starter/`.
In the repository:

1. **Copy the starter's `app/`** over the scaffold's: it replaces
   `app/index.ts` and adds `app/storage.ts`, `app/ui/`, `app/dev/` and
   `app/package.json`. Keep the scaffold's `app/identity.ts`: the starter
   imports it.
2. **Merge the starter's `gitignore`** into the repository's `.gitignore`
   (create it if missing). `app/.ui-build/` must be in it: CI removes a
   committed copy and warns.
3. **Put the artifact in.**
   - React: its component becomes `app/ui/Artifact.tsx` (or `.jsx`),
     replacing the placeholder, its default export unchanged. Its imports
     resolve to the packages from step 3.
   - HTML: follow `references/html-artifacts.md`.
4. **Replace `APP_TITLE`** in `app/index.ts` and `app/ui/AppBar.tsx` with
   the app's title (plain text, no markup).
5. **Rewrite what step 4 removed or changed**, and nothing else. Keep every
   `window.storage` call as it is: `app/ui/storage-shim.ts` gives it the same
   shape (`get`, `set`, `delete`, `list`, with `true` last for shared). If the
   artifact relied on a storage behavior the reference marks as unverified,
   test that path in step 7.
6. **Dependencies.** Add each library from step 3 to `dependencies` in
   `app/package.json` at its pinned version (the interface's packages are
   audited like the Worker's, so never under `devDependencies`), then run
   `npm install` in `app/` and commit `app/package-lock.json`. Prefer
   versions that have been out a few weeks: when the platform sets a
   release-age cooldown, a version newer than it fails that gate, which
   names the package.
7. **`CLAUDE.md`.** Keep every section the scaffold's `CLAUDE.md` has (CI
   checks its headers) and add a short section after the first, naming this
   as a converted Claude artifact, the `app/ui/` layout, `npm run dev`, the
   personal and shared storage, and that the repository is now the source of
   truth.

Do not add a root `package.json`, any `wrangler.*` file or a `.wrangler/`
directory: `app/dev/serve.mjs` keeps its local config under the ignored
`app/.dev/`.

## 7. Try it locally

In `app/`: `npm run dev`, then open `http://localhost:8787`. It builds the
interface as CI does, runs the Worker with a local database, and signs the
user in as a stand-in person (`DEV_USER=<address> npm run dev` changes who).
Check, with the user:

- the artifact looks and behaves as it did on claude.ai;
- the browser console shows no Content-Security-Policy errors (a library
  that injects `<style>` tags or loads from a CDN shows one here; fix it as
  `references/libraries.md` says);
- personal data stays with one person: save something, restart with another
  `DEV_USER`, and check it is not there, while shared data is;
- the keyboard alone completes each main flow, and focus is visible.

## 8. Review before shipping

Walk the app against `get_app_security` (sections 3, 4, 9 and 12 above all:
escaping, input bounds, headers, forged requests; the starter covers 9 and
12 for its own routes, so check any route you added) and against
`get_app_accessibility` (a page title, `lang`, labeled controls, visible
focus, real buttons instead of clickable `<div>`s). An artifact written for
a quick demo often needs the accessibility pass more than anything else:
present the findings and fix them with the user's agreement.

## 9. Hand off

Tell the user the app is registered and built, then run
`inno-safety-preflight` (it pushes to the default branch, which runs the
real gates, the interface build among them, and deploys nothing), then
`inno-ship`. Tell them the app starts members-only, and that widening it to
everyone who signs in goes through `inno-manage-app` after it ships. Quote
the first-deploy deadline from `register_app`'s second answer, as
`inno-new-app` section 5 says.
