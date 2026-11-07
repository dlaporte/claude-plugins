// Local runs only: serves the app at http://localhost:8787 the way the
// platform's front door would, signed in as a stand-in person. It starts
// `wrangler dev` with a local D1 (its config kept in the ignored .dev/
// directory, since the repository may hold no wrangler config) behind a small
// proxy that adds the front door's identity headers. Nothing here ships: the
// deployed app's headers come from the real front door.
//
// Both answer this machine only, since each takes a caller at its word: the
// proxy signs everyone in as DEV_USER, and the Worker trusts whatever
// X-Forwarded-* headers reach it. Both listen on 127.0.0.1, and both refuse
// (403) a request whose Host is not localhost or 127.0.0.1 at the proxy's
// port: the proxy before it forwards, and the Worker through the entry this
// writes to .dev/entry.mjs, since wrangler dev hands the Worker the Host it
// was sent (the proxy forwards the browser's). A web page elsewhere that
// points its own name at this machine (DNS rebinding) sends its own name, to
// either port, so both refuse it.
//
// The proxy serves its own Worker, and lives as long as it does. wrangler dev
// takes a port of its own (a free one, or DEV_WORKER_PORT), and until that
// port answers as this run's Worker the proxy forwards nothing: it answers
// 503. The entry's refusal carries a token made for this run, so another
// process on the port, a stale wrangler dev included, is never taken for it,
// and startup fails instead. wrangler dev runs in a process group of its own:
// if it cannot start, or exits, the proxy closes and this script exits 1, and
// when this script is stopped (Ctrl-C, SIGTERM or SIGHUP) it stops the whole
// group, the workerd under wrangler dev included, and exits 0.
//
// Usage (in app/): npm run dev
//   DEV_USER=someone@example.edu   who is signed in (dev@example.edu)
//   DEV_PORT=8790                  the proxy's port (8787), to run two apps at once
//   DEV_WORKER_PORT=8791           wrangler dev's port (by default, any free one)
import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { mkdirSync, writeFileSync } from "node:fs";
import http from "node:http";
import net from "node:net";
import { setTimeout as sleep } from "node:timers/promises";
import { wranglerConfig } from "./wrangler-config.mjs";

const USER = process.env.DEV_USER ?? "dev@example.edu";
const PORT = port("DEV_PORT") ?? 8787;
const ASKED = port("DEV_WORKER_PORT");
const HOSTS = new Set([`localhost:${PORT}`, `127.0.0.1:${PORT}`]);
const REFUSAL = `This development server answers only http://localhost:${PORT} and http://127.0.0.1:${PORT}.\n`;
// This run's name: wrangler dev hands it to the entry, whose refusals carry it.
const INSTANCE = randomUUID();
const READY_SECONDS = 60;
const TEXT = { "Content-Type": "text/plain; charset=utf-8" };

if (ASKED === PORT) fail("DEV_WORKER_PORT must differ from DEV_PORT");

let worker = null;
let workerPort = null;
let ready = false;
let stopping = false;

/** The port number in environment variable `name`, or undefined when it is unset. */
function port(name) {
  const value = process.env[name];
  if (value === undefined || value === "") return undefined;
  const n = Number(value);
  if (!/^\d+$/.test(value) || n < 1 || n > 65535) fail(`${name} must be a port number from 1 to 65535, not ${JSON.stringify(value)}`);
  return n;
}

function fail(why) {
  console.error(`dev: ${why}`);
  process.exit(2);
}

/** A port nothing listens on, from the operating system, other than `not`. */
function freePort(not) {
  return new Promise((resolve, reject) => {
    const s = net.createServer().once("error", reject).listen(0, "127.0.0.1", () => {
      const { port: free } = s.address();
      s.close(() => (free === not ? freePort(not).then(resolve, reject) : resolve(free)));
    });
  });
}

/** Sends `signal` to wrangler dev's process group; false once none of it is left. */
function signalGroup(signal) {
  try {
    process.kill(-worker.pid, signal);
    return true;
  } catch {
    return false;
  }
}

/**
 * Closes the proxy, stops wrangler dev's whole process group (asking first,
 * then, after 5 seconds, forcing it) and exits with `code`, saying `why`
 * first when given. Runs once.
 */
function stop(code, why) {
  if (stopping) return;
  stopping = true;
  ready = false;
  if (why) console.error(`dev: ${why}`);
  server.close();
  server.closeAllConnections();
  if (!worker?.pid || !signalGroup("SIGTERM")) process.exit(code);
  const until = Date.now() + 5000;
  const check = setInterval(() => {
    if (signalGroup(0) && Date.now() < until) return;
    clearInterval(check);
    signalGroup("SIGKILL");
    process.exit(code);
  }, 100);
}

/**
 * What wrangler dev's port answers to a request under its own name, which the
 * entry refuses: this run's token, "" for an answer without it, or null for
 * no answer yet.
 */
function probe() {
  return new Promise((resolve) => {
    const req = http.get(
      { host: "127.0.0.1", port: workerPort, path: "/", headers: { host: `127.0.0.1:${workerPort}` }, timeout: 2000, agent: false },
      (res) => {
        res.resume();
        resolve(String(res.headers["x-dev-instance"] ?? ""));
      },
    );
    req.on("timeout", () => req.destroy());
    req.on("error", () => resolve(null));
  });
}

async function start() {
  workerPort = ASKED ?? (await freePort(PORT));
  // wrangler dev's devtools inspector takes a port too. Its default is one
  // port for every checkout, and two started together collide on it.
  const inspectorPort = await freePort(workerPort);
  worker = spawn(
    "npx",
    [
      "--no-install", "wrangler", "dev", "--config", ".dev/wrangler.jsonc",
      "--ip", "127.0.0.1", "--port", String(workerPort),
      "--inspector-ip", "127.0.0.1", "--inspector-port", String(inspectorPort),
      "--var", `DEV_INSTANCE:${INSTANCE}`,
    ],
    // Its own process group, so stopping it stops what it started too; and
    // no terminal input, which a background group may not read.
    { stdio: ["ignore", "inherit", "inherit"], detached: true },
  );
  worker.on("error", (e) => stop(1, `could not start wrangler dev: ${e.message}`));
  worker.on("exit", (code, signal) => stop(1, `wrangler dev stopped (${signal ?? `exit code ${code}`}), so the proxy has closed`));

  const until = Date.now() + READY_SECONDS * 1000;
  while (!stopping) {
    const answer = await probe();
    if (stopping) return;
    if (answer === INSTANCE) {
      ready = true;
      console.log(`http://localhost:${PORT}, signed in as ${USER} (wrangler dev on 127.0.0.1:${workerPort}, its inspector on 127.0.0.1:${inspectorPort})`);
      return;
    }
    if (answer !== null) {
      return stop(1, `port ${workerPort} answers, but not as this run's Worker: another process may hold it (set DEV_WORKER_PORT to a free port), or the Worker failed to load (see above)`);
    }
    if (Date.now() > until) return stop(1, `wrangler dev did not answer on port ${workerPort} within ${READY_SECONDS} seconds (see above)`);
    await sleep(200);
  }
}

mkdirSync(".dev", { recursive: true });
writeFileSync(".dev/entry.mjs", [
  "// Written by dev/serve.mjs, for local runs only: the app's Worker, refusing",
  "// a request whose Host is not one the proxy answers to. A refusal carries",
  "// this run's token (DEV_INSTANCE, which serve.mjs gives wrangler dev), so",
  "// serve.mjs can tell its own Worker from another process on the port.",
  'import app from "../index.ts";',
  `const HOSTS = new Set(${JSON.stringify([...HOSTS])});`,
  "export default {",
  "  ...app,",
  "  fetch(request, env, ctx) {",
  '    if (!HOSTS.has(request.headers.get("host") ?? "")) {',
  `      return new Response(${JSON.stringify(REFUSAL)}, { status: 403, headers: { "Content-Type": "text/plain; charset=utf-8", "X-Dev-Instance": env.DEV_INSTANCE } });`,
  "    }",
  "    return app.fetch(request, env, ctx);",
  "  },",
  "};",
  "",
].join("\n"));
writeFileSync(".dev/wrangler.jsonc", JSON.stringify(wranglerConfig("entry.mjs"), null, 2));

const server = http.createServer((req, res) => {
  if (!HOSTS.has(req.headers.host ?? "")) {
    res.writeHead(403, TEXT);
    res.end(REFUSAL);
    return;
  }
  if (!ready) {
    res.writeHead(503, TEXT);
    res.end("wrangler dev is starting: reload in a moment.\n");
    return;
  }
  const headers = { ...req.headers };
  for (const h of Object.keys(headers)) if (h.startsWith("x-forwarded-")) delete headers[h];
  Object.assign(headers, {
    "x-forwarded-user": USER,
    "x-forwarded-email": USER,
    "x-forwarded-subject": `dev-${USER}`,
    "x-forwarded-groups": "",
    "x-forwarded-host": `localhost:${PORT}`,
    "x-forwarded-proto": "http",
  });
  const up = http.request({ host: "127.0.0.1", port: workerPort, path: req.url, method: req.method, headers }, (r) => {
    res.writeHead(r.statusCode ?? 502, r.headers);
    r.pipe(res);
  });
  up.on("error", () => {
    if (res.headersSent) return res.destroy();
    res.writeHead(502, TEXT);
    res.end("wrangler dev did not answer: see the terminal running npm run dev.\n");
  });
  req.pipe(up);
});

for (const signal of ["SIGINT", "SIGTERM", "SIGHUP"]) process.on(signal, () => stop(0));
// Whatever ends this script, wrangler dev's group does not outlive it.
process.on("exit", () => worker?.pid && signalGroup("SIGKILL"));
server.on("error", (e) => {
  stop(1, e.code === "EADDRINUSE" ? `port ${PORT} is in use: stop what holds it, or set DEV_PORT to a free port` : `the proxy failed: ${e.message}`);
});
server.listen(PORT, "127.0.0.1", () => {
  start().catch((e) => stop(1, `could not start wrangler dev: ${e.message}`));
});
