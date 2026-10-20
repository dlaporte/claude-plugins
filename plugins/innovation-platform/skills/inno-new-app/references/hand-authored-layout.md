# The empty-repo path: hand-authoring the layout

Read this from `inno-new-app` §4 when the repo wasn't template-derived: call 2
of `register_app` had nothing to prune, so the repo has none of its type's
files. Hand-author the full layout out of the template repo (the
`Template repo:` line of the status you read in the Version gate), then write
`.github/workflows/deploy.yml` from call 2's response. Where you copy from
depends on the type, because three of the four have an overlay directory:

- **`function` / `mcp-function`:** copy `scaffold/function/` or
  `scaffold/mcp-function/`. Each carries `CLAUDE.md`, `README.md`, and an
  `app/` (`index.ts`, the identity helper `identity.ts` in a template from
  platform v0.16.19, plus `package.json` and its lockfile for
  `mcp-function`). Take `.gitignore` from the template root.
- **`mcp-container`:** copy `scaffold/mcp-container/`:
  `CLAUDE.md`, `README.md`, `app/main.py`, and `app/requirements.txt`. Fill
  in the rest from the template root, which the overlay does not carry:
  `Dockerfile`, `.dockerignore`, `lib/`, `app/storage.py`, and `.gitignore`
  (skip `app/templates/`, which this type has no use for).
- **`container`:** there is no `scaffold/container/`, because the container
  files ARE the template root. Copy those: `Dockerfile`, `.dockerignore`,
  `lib/`, `app/main.py`, `app/storage.py`, `app/templates/`,
  `app/requirements.txt`, the root `CLAUDE.md`, `README.md`, and `.gitignore`.

Copy `CLAUDE.md` rather than writing one: the `config-integrity` gate checks
five required section headers, and the check is **type-blind**, so a container
app carrying the function headers passes and the reverse passes as well.
`inno-platform-conventions`' **Files you must not touch** section names the
five and the two variant groups. Copy your own type's version anyway, so the
body describes the runtime this app actually has.

**An anonymous app** (registered with `identity: "anonymous"`): after the
type's files, copy `scaffold/anonymous/<type>/CLAUDE.md` from the template
repo over the `CLAUDE.md` you just copied, as the platform's scaffold commit
does for a template-derived repo. It carries the same five headers, and its
Identity section is this app's rule: no identity header read, no sign-out
link, the contract's R10, its cookie rule and the uploaded-file rule. A
template with no `scaffold/anonymous/` predates anonymous apps: tell the
user, and write the app to R10 (`get_app_contract` with `sections: ["2"]`)
and `inno-platform-conventions`' **An anonymous app: R10**.

Then go back to `inno-new-app` §4 and scaffold by the deployment type.
