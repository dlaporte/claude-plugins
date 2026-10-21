# Recipe sketches: Node and Go

Read this from `inno-containerize` when the app is a Node app, or a Go (or
similar compiled) app. Each sketch meets the same contract as the Python
reference recipe in `SKILL.md`; take the base from the current pinned refs
`get_app_contract` serves. Each comment sits on a line of its own, above its
instruction, for the reason `SKILL.md` gives.

## Node

```dockerfile
# Use the current pinned ref from get_app_contract.
FROM node:24-slim
RUN apt-get update && apt-get -y upgrade && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY app/package*.json ./
RUN npm ci --omit=dev
COPY app/ .
# The official node images ship this user.
USER node
EXPOSE 8080
# The server must bind 0.0.0.0:8080 and serve /healthz.
CMD ["node", "server.js"]
```

## Go (multi-stage; only the runtime stage ships)

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
# The server must bind 0.0.0.0:8080 and serve /healthz.
CMD ["/server"]
```
