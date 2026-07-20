---
name: inno-containerize
description: Use when writing or editing the Dockerfile for an inno-{app} repo. Encodes the exact contract the platform's container gate (Trivy + non-root/port checks) requires — base image, patching, user, port, healthcheck.
---

# inno-containerize

The `container` CI job builds your Dockerfile with **no deploy credentials
present** (an app author fully controls this build's inputs, and nothing of
platform value is reachable from it), then runs three checks: a Trivy image
scan, a non-root-user assertion, and an `EXPOSE 8080` assertion. All three
must pass before `deploy` (which needs `container` to have succeeded) will
run. `wrangler deploy` rebuilds the same Dockerfile a second time at deploy
time, so a Dockerfile that only works "sometimes" will eventually break a
deploy that passed CI.

## The complete, copy-pasteable Dockerfile

```dockerfile
FROM python:3.12-slim

# Patch base-image OS packages so the image passes the platform's Trivy
# HIGH/CRITICAL gate (Debian slim ships with fixable CVEs even freshly pulled).
RUN apt-get update && apt-get -y upgrade && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install pinned deps first (better layer caching), then copy the app,
# INCLUDING templates/ — a missing templates dir is a common runtime 500
# (Jinja2Templates("templates") raises at import time if the dir is absent).
COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app/ .

# Non-root BEFORE CMD — Trivy/the container-validate gate reject images
# whose Config.User is empty, "root", or "0".
RUN useradd -m appuser
USER appuser

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://localhost:8080/healthz').status==200 else 1)"

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
```

## Why each line is load-bearing

- **`python:3.12-slim` + `apt-get upgrade`**: the CI `container` job runs
  `aquasec/trivy:0.63.0 image --severity HIGH,CRITICAL --ignore-unfixed
  --exit-code 1` against the built image. A stock slim base commonly has
  fixable OS-package CVEs; skipping the upgrade line is the #1 cause of a
  Trivy gate failure that has nothing to do with your app code.
- **`COPY app/ .` after installing requirements**: copy order matters for
  build cache, but the requirement that matters for correctness is that
  `app/` is copied *whole*, so `templates/` comes along. If you restructure
  the repo, keep the Dockerfile's `COPY app/ .` in sync with wherever
  `templates/` actually lives.
- **`useradd -m appuser` then `USER appuser` before `CMD`**: the gate
  literally inspects `docker inspect --format='{{.Config.User}}'` and fails
  if it's empty/root/0. Setting `USER` after your last `RUN` that needs root
  (e.g. `apt-get`, `pip install` into system site-packages) is the correct
  order — don't switch user earlier and then try to `pip install` as
  `appuser` unless you've also fixed permissions.
- **`EXPOSE 8080`**: the gate also inspects `Config.ExposedPorts` for
  literally `"8080/tcp"`. The gateway forwards all container traffic to this
  port regardless of what you `EXPOSE` — mismatching it doesn't just fail the
  gate, the app won't receive traffic in production either.
- **`/healthz` + `HEALTHCHECK`**: your app must serve `GET /healthz` -> HTTP
  200 (JSON body is fine, e.g. `{"status": "ok"}`) for both the Docker
  `HEALTHCHECK` and the platform's runtime health monitoring. Missing this
  doesn't fail CI directly but causes health-check timeouts in production.
- **`uvicorn main:app --host 0.0.0.0 --port 8080`**: binding to `127.0.0.1`
  instead of `0.0.0.0` is a classic "works locally, unreachable in the
  container" bug — the gateway connects from outside the container network
  namespace.

## Local sanity check before pushing

```bash
docker build -t app-under-test .
docker inspect --format='{{.Config.User}}' app-under-test        # must not be empty/root/0
docker inspect --format='{{json .Config.ExposedPorts}}' app-under-test | grep '8080/tcp'
docker run -d -p 8080:8080 --name app-under-test-run app-under-test
curl -sf http://localhost:8080/healthz
docker rm -f app-under-test-run
```

If you have Trivy installed locally, also run it before pushing (this
mirrors the `container` CI job exactly):

```bash
trivy image --severity HIGH,CRITICAL --ignore-unfixed app-under-test
```
