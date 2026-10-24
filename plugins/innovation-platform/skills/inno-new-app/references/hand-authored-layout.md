# The empty-repo path: hand-authoring the layout

Read this from `inno-new-app` §4 when the repo wasn't template-derived: call 2
of `register_app` had nothing to prune, so the repo has none of its type's
files. Hand-author the full layout out of the template repo (the
`Template repo:` line of the status you read in the Version gate), then write
`.github/workflows/deploy.yml` from call 2's response. Where you copy from
depends on the type, because three of the four have an overlay directory:

- **`function` / `mcp-function`:** copy `scaffold/function/` or
  `scaffold/mcp-function/`. Each carries `CLAUDE.md`, `README.md`, and an
  `app/` (`index.ts`, the identity helper `identity.ts`, plus `package.json`
  and its lockfile for `mcp-function`). Take `.gitignore` from the template
  root.
- **`mcp-container`:** copy `scaffold/mcp-container/`:
  `CLAUDE.md`, `README.md`, `app/main.py`, and `app/requirements.txt`. Fill
  in the rest from the template root, which the overlay does not carry:
  `Dockerfile`, `.dockerignore`, `lib/`, `app/storage.py`, and `.gitignore`
  (skip `app/templates/`, which this type has no use for).
- **`container`:** there is no `scaffold/container/`, because the container
  files ARE the template root. Copy those: `Dockerfile`, `.dockerignore`,
  `lib/`, `app/main.py`, `app/storage.py`, `app/templates/`,
  `app/requirements.txt`, the root `CLAUDE.md`, `README.md`, and `.gitignore`.

Never copy an overlay's `.scaffold-remove`: it tells the platform's scaffold
commit what to delete and has no use in an app.

## Which `CLAUDE.md` to start from

This is the plugin's one home for it: `inno-platform-conventions` (whose
**Files you must not touch** names the headers the gate checks) and
`inno-migrate-app` point here.

- **An identity-aware app** starts from its type's guide:
  `scaffold/function/CLAUDE.md`, `scaffold/mcp-function/CLAUDE.md` or
  `scaffold/mcp-container/CLAUDE.md` for those three types, and the template
  root's `CLAUDE.md` for `container`.
- **An anonymous app** starts from its type's anonymous guide,
  `scaffold/anonymous/<type>/CLAUDE.md`, for all four types
  (`scaffold/anonymous/container/` included). Its rules are this app's:
  its Identity section (no identity header read, no sign-out link, the
  contract's R10, its cookie rule, where the promise ends) and its
  Persistence section's **Files someone uploaded** paragraph (the
  uploaded-file rule).
- **A repo that already has a `CLAUDE.md`** (a migrated one) keeps it.
  Never replace it: with the user's okay, merge the five required sections
  of the guide above into it, each header with the guide's text under it,
  and leave the rest of the file as it is.

Start from the guide rather than writing one: the `config-integrity` gate
checks five required section headers, and the check is **type-blind**, so a
container app carrying the function headers passes and the reverse passes as
well. Take your own type's guide anyway, so the body describes the runtime
this app actually has, and rewrite the rest of the body to describe the app.

## An anonymous app's files

For an app registered with `identity: "anonymous"`, after the type's files,
copy the files of `scaffold/anonymous/<type>/` from the template repo over
them, then read its `.scaffold-remove` without copying it and delete the
paths it lists (one path per line; an entry ending `/` is a directory), as
the platform's scaffold commit does for a template-derived repo. That lays
the anonymous guide (above) and reference entry files that read no identity,
and for a function-shaped type it deletes `app/identity.ts`; a container
type's storage client keeps its identity helper, which the app never calls.
A template whose `scaffold/anonymous/<type>/` holds only a `CLAUDE.md` is
older than the layer's reference code: keep the type's entry files and
remove their identity reads as you build (`app/identity.ts` and its calls in
a function-shaped repo, the storage helper's calls in a container one, a
`/me` route, a sign-out footer, a `whoami` tool). A template with no
`scaffold/anonymous/` predates anonymous apps: tell the user, and write the
app to R10 (`get_app_contract` with `sections: ["R10"]`) and
`inno-platform-conventions`' **An anonymous app: R10**.

Then go back to `inno-new-app` §4 and scaffold by the deployment type.
