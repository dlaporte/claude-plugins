---
name: inno-containerize
description: Use when writing or editing the Dockerfile for an inno-{app} repo. Encodes the exact contract the platform's container gate requires (non-root, port 8080, patched base, CVE-clean image) for ANY stack, with reference recipes.
---

# inno-containerize

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

**Container-type apps only.** This skill is for the `container` deployment
type — and applies equally to `mcp-container`: an mcp-container image follows
this exact same Dockerfile contract, plus it serves `POST /mcp`. A
**`function`-type** app (its own Cloudflare Worker behind the gateway)
has **no Dockerfile** — the container CI gates below are skipped for it, and
its entry is `app/index.ts`, not a container image (see `get_app_contract`
§1.1 and `inno-platform-conventions`). If the app is function-shaped (`function` or `mcp-function`), skip this
skill entirely.

The `container` CI job builds your Dockerfile with **no deploy credentials
present** (an app author fully controls this build's inputs, and nothing of
platform value is reachable from it), then runs four checks: a Trivy image
scan, a non-root-user assertion, an `EXPOSE 8080` assertion, and a
**`GET /healthz` smoke test** against the built image. The Trivy scan is
policy-toggleable per app (`safety.gate.trivy`, admin-set): when enabled it
hard-fails on HIGH/CRITICAL findings that have a fix available
(`--severity HIGH,CRITICAL --ignore-unfixed`); when disabled the scan step
is skipped and the job prints a loud `SAFETY GATE DISABLED` warning instead.
The other three checks are not policy-toggleable and always run. A
CycloneDX SBOM of the built image is generated and uploaded to the broker
regardless of the Trivy gate's setting. A gate-disabled app sits outside
image-vulnerability policy entirely, at this gate and in the daily safety
sweep alike, which skips apps whose gate is off. The SBOM is captured
anyway so that re-enabling the gate restores sweep coverage immediately,
with no new deploy needed to regenerate it. Every check that runs must
pass before `deploy` (which needs `container` to have succeeded) will run.

The image the gates scanned is the image that ships. On a `v*` tag run the
`container` job saves that exact image as a workflow artifact; the `deploy`
job loads it, refuses unless its id matches the id the `container` job
recorded with the platform, pushes it, and pins the deployment to its digest.
Nothing rebuilds your Dockerfile at deploy time. Each run still builds its own
image, though, so the tag run's scan can see a different image than the
push preflight did when the base tag floats or upstream packages
changed in between: pin the base to the digest `get_app_contract` serves.

## The contract — identical for every stack

1. **Listen on `0.0.0.0:8080`** and declare `EXPOSE 8080` — the gate
   inspects `Config.ExposedPorts` for literally `"8080/tcp"`, and the
   gateway forwards traffic there regardless. Binding `127.0.0.1` is the
   classic "works locally, unreachable in the container" bug.
2. **Non-root `USER` before `CMD`**: the gate is an allowlist. It checks the
   part of `Config.User` before any `:` (the group is not checked) and accepts
   exactly two forms:
   - a plain decimal uid from 1 to 2147483647, such as `USER 1000` or
     `USER 65532:65532` (leading zeros count as Docker counts them, so
     `USER 00` is uid 0);
   - a user name made only of letters, digits, `.`, `_` and `-`, not starting
     with `-`, that appears on exactly one line of the image's own
     `/etc/passwd` (copied out of the image, never run), where that line's uid
     field is plain digits from 1 to 2147483647.

   Everything else is refused: `root` or any uid 0, an unset `USER`, a signed
   uid (`+0`), an empty user part (`:1000`), a name missing from
   `/etc/passwd`, a name on more than one line (or on a line with leading
   blanks, or with blanks inside the name field), a uid field that is not a
   plain number, a uid above
   2147483647, and a named user in an image with no readable `/etc/passwd`.
   The platform enforces this exact rule from platform v0.14.4 (contract
   version 13); earlier releases refuse a subset of these. On `scratch` or any
   base without a passwd file, use a numeric uid (`USER 65532`). Switch user
   *after* your last root-requiring `RUN`.
3. **CVE-clean image** — patch the base's OS packages in the build
   (`apt-get upgrade` / `apk upgrade`) so the Trivy gate passes; a stock
   base commonly ships fixable CVEs that have nothing to do with your code.
4. **`GET /healthz` → 200** — a **hard CI gate**, not a nicety. The
   `container` job runs the built image (`docker run -d -p 8080:8080`) and
   polls `/healthz` 18 times with a 5s sleep (~90s); if nothing answers 200
   it dumps the container logs and fails the job, which fails `deploy`. The
   platform's runtime health probe binds to the same endpoint after deploy
   (immediately on each green deploy, then daily). Keep it cheap and
   **storage-independent** — a slow app boot is legitimate, a `/healthz`
   that waits on storage is not. Never stub it as a TODO.
5. **Keep build inputs where the gates allow them.** Put the app's code and
   manifests under `app/` (an `app/src/` is fine); a repo-root `src/` is
   platform-owned and the `config-integrity` gate fails any file in it. Never
   commit a `.npmrc` anywhere, `app/.npmrc` included, even for a container
   build that would use it: npm expands environment variables into it, so the
   gate rejects it at every depth. Other package-manager config
   (`.yarnrc.yml`, `pnpm-workspace.yaml`, `bunfig.toml`) is allowed under
   `app/` but not at the repo root. **Never commit a symlink that points at a
   directory**, anywhere in the repo, dangling ones included; a link to a
   *file* is fine. The gate walks the tree without following links, so content
   behind a directory link is never inspected, and there is no policy toggle
   to waive it (contract version 14). Copy the real directory in, or produce
   it during the image build.

**Base image: call the `get_app_contract` MCP tool for the platform's
current digest-pinned recommended bases (python/node/go) — never hard-code
a digest from this skill, documentation, or memory.** Any base that passes
these checks is allowed; the recommendations are simply known-good.

**Runtime config never lives in the image.** App-level values (API keys,
base URLs) arrive as real environment variables from the platform's
Variables facility (`set_app_variable` / the app page's Variables tab) —
never `ENV`/`ARG` a secret into the committed Dockerfile: the image is
built in CI from the repo, so a baked-in value is a committed one, and
gitleaks fails the build.

**The Dockerfile is scanned too.** The `sast` gate runs semgrep over the whole
repository except the repo-root `src/` and semgrep's default-ignored
directories (`test/`, `tests/`, `build/`, `dist/`, `vendor/`, `node_modules/`,
at any depth), because the docker build context is the repo root: the
Dockerfile and any root-level file it `COPY`s are checked, not only `app/`.

## Reference recipe — Python (the platform's tested stack)

This is the template's Dockerfile; it ships in the `inno-template` scaffold a
container app is created from.

```dockerfile
FROM python:3.12-slim          # or the current pinned ref from get_app_contract
RUN apt-get update && apt-get -y upgrade && rm -rf /var/lib/apt/lists/*

WORKDIR /app
# Install pinned deps first (layer caching), then copy app/ WHOLE — a missing
# templates/ dir is a common runtime 500 (Jinja2Templates raises at import).
COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app/ .

RUN useradd -m appuser
USER appuser

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://localhost:8080/healthz').status==200 else 1)"
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
```

## Recipe sketch — Node

```dockerfile
FROM node:24-slim              # use the current pinned ref from get_app_contract
RUN apt-get update && apt-get -y upgrade && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY app/package*.json ./
RUN npm ci --omit=dev
COPY app/ .
USER node                      # the official node images ship this user
EXPOSE 8080
CMD ["node", "server.js"]      # server must bind 0.0.0.0:8080 and serve /healthz
```

## Recipe sketch — Go (multi-stage; only the runtime stage ships)

```dockerfile
FROM golang:1-alpine AS build
WORKDIR /src
COPY app/ .
RUN CGO_ENABLED=0 go build -o /server .

# Runtime stage: use the current pinned distroless ref from get_app_contract.
# :nonroot variants satisfy the non-root gate with no useradd needed.
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /server /server
EXPOSE 8080
CMD ["/server"]                # must bind 0.0.0.0:8080 and serve /healthz
```

## Local sanity check before pushing

The block below builds the image, then decides the non-root rule exactly the
way the CI gate does (item 2 above) and prints one `OK:` or `FAIL:` line. It
never runs the image to resolve the user: it reads `/etc/passwd` straight off
the image, maps NUL bytes before reading, and hands the name to `awk` through
the environment. It has no comments and no `!` outside single quotes, so it
pastes cleanly into bash, zsh, or an interactive zsh. The last three commands
are the `/healthz` smoke gate in one shot. If `docker build` fails, fix that
first: the checks below read the last image that built, and with no image at
all they print a misleading root `FAIL`.

```bash
docker build -t app-under-test .
user="$(docker inspect --format='{{.Config.User}}' app-under-test | tr '\000' '\001')"
u="${user%%:*}"; uid=""; why=""
case "$user" in 0|root|0:*|root:*|"") why="runs as root" ;; esac
if [ -z "$why" ]; then
  case "$u" in
    "") why="has an empty user part, which Docker runs as uid 0" ;;
    *[^0123456789]*)
      case "$u" in
        -*|*[^ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-]*)
          why="is neither a plain uid nor a portable user name" ;;
        *)
          docker rm -f uidprobe >/dev/null 2>&1
          docker create --name uidprobe app-under-test >/dev/null 2>&1
          pw="$(docker cp uidprobe:/etc/passwd - 2>/dev/null | tar -xO 2>/dev/null | tr '\000' '\001')"
          docker rm -f uidprobe >/dev/null 2>&1
          if [ -z "$pw" ]; then
            why="cannot be resolved: the image has no readable /etc/passwd"
          else
            uid="$(printf '%s\n' "$pw" | U="$u" LC_ALL=C awk -F: '
              { line = $0; sub(/^[^!-~]+/, "", line); sub(/[^!-~]+$/, "", line)
                split(line, f, ":"); if (f[1] == ENVIRON["U"]) loose++
                if ($1 == ENVIRON["U"]) { exact++; field = $3 } }
              END { if (loose == 0 && exact == 0) print "none"
                    else if (loose != 1 || exact != 1) print "ambiguous"
                    else if (field !~ /^[0-9]+$/) print "malformed"
                    else print field }')"
            case "$uid" in
              none) why="matches no /etc/passwd entry" ;;
              ambiguous) why="matches /etc/passwd ambiguously (on more than one line, or on a line with leading blanks, or with blanks inside the name field)" ;;
              malformed) why="matches an /etc/passwd line whose uid field is not a plain number" ;;
            esac
          fi ;;
      esac ;;
    *) uid="$u" ;;
  esac
fi
n="$(printf '%s' "$uid" | sed 's/^0*//')"
if [ -z "$why" ] && [ -z "$n" ]; then why="resolves to uid 0"; fi
if [ -z "$why" ] && { [ "${#n}" -gt 10 ] || [ "$n" -gt 2147483647 ]; }; then why="resolves to a uid above 2147483647"; fi
shown="$(printf '%s' "$user" | LC_ALL=C tr -c ' -~' '?')"
if [ -z "$why" ]; then echo "OK: User='$shown' runs as uid $n"; else echo "FAIL: User='$shown' $why"; fi
docker inspect --format='{{json .Config.ExposedPorts}}' app-under-test | grep '8080/tcp'
docker run -d -p 8080:8080 --name app-under-test-run app-under-test
curl -sf http://localhost:8080/healthz
docker rm -f app-under-test-run
```

If you have Trivy installed locally, mirror the CI gate's severity policy
before pushing (the exact scanner version is CI's business, not yours):

```bash
trivy image --severity HIGH,CRITICAL --ignore-unfixed app-under-test
```
