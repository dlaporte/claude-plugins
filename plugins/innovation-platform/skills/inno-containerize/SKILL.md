---
name: inno-containerize
description: Use when writing or editing the Dockerfile for an inno-{app} repo. Encodes the exact contract the platform's container gate requires (non-root, port 8080, patched base, CVE-clean image) for ANY stack, with reference recipes.
---

# inno-containerize

**Container-type apps only.** This skill is for the `container` deployment
type. A **`worker`-type** app (its own Cloudflare Worker behind the gateway)
has **no Dockerfile** — the container CI gates below are skipped for it, and
its entry is `app/index.ts`, not a container image (see `get_app_contract`
§1.1 and `inno-platform-conventions`). If the app is a worker, skip this
skill entirely.

The `container` CI job builds your Dockerfile with **no deploy credentials
present** (an app author fully controls this build's inputs, and nothing of
platform value is reachable from it), then runs three checks: a Trivy image
scan (HIGH/CRITICAL, `--ignore-unfixed`, hard fail), a non-root-user
assertion, and an `EXPOSE 8080` assertion. All three must pass before
`deploy` (which needs `container` to have succeeded) will run.
`wrangler deploy` rebuilds the same Dockerfile a second time at deploy
time, so a Dockerfile that only works "sometimes" will eventually break a
deploy that passed CI.

## The contract — identical for every stack

1. **Listen on `0.0.0.0:8080`** and declare `EXPOSE 8080` — the gate
   inspects `Config.ExposedPorts` for literally `"8080/tcp"`, and the
   gateway forwards traffic there regardless. Binding `127.0.0.1` is the
   classic "works locally, unreachable in the container" bug.
2. **Non-root `USER` before `CMD`** — the gate inspects
   `docker inspect --format='{{.Config.User}}'` and fails on
   empty/`root`/`0`. Switch user *after* your last root-requiring `RUN`.
3. **CVE-clean image** — patch the base's OS packages in the build
   (`apt-get upgrade` / `apk upgrade`) so the Trivy gate passes; a stock
   base commonly ships fixable CVEs that have nothing to do with your code.
4. **`GET /healthz` → 200** — reserved for platform health monitoring
   (CI does not probe it today; platform features bind to it without
   notice). Keep it cheap and storage-independent.

**Base image: call the `get_app_contract` MCP tool for the platform's
current digest-pinned recommended bases (python/node/go) — never hard-code
a digest from this skill, documentation, or memory.** Any base that passes
the three checks is allowed; the recommendations are simply known-good.

## Reference recipe — Python (the platform's tested stack)

This is the template's Dockerfile; it ships with every generated repo.

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

```bash
docker build -t app-under-test .
docker inspect --format='{{.Config.User}}' app-under-test        # must not be empty/root/0
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
