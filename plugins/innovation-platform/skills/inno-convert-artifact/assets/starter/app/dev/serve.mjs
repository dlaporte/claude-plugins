// Local runs only: serves the app at http://localhost:8787 the way the
// platform's front door would, signed in as a stand-in person. It starts
// `wrangler dev` with a local D1 on port 8788 (config kept in the ignored
// .dev/ directory, since the repository may hold no wrangler config) and a
// small proxy in front that adds the front door's identity headers. Nothing
// here ships: the deployed app's headers come from the real front door.
//
// Both answer this machine only, since each takes a caller at its word: the
// proxy signs everyone in as DEV_USER, and the Worker trusts whatever
// X-Forwarded-* headers reach it. Both listen on 127.0.0.1, and both refuse
// (403) a request whose Host is not localhost:8787 or 127.0.0.1:8787: the
// proxy before it forwards, and the Worker through the entry this writes to
// .dev/entry.mjs, since wrangler dev hands the Worker the Host it was sent
// (the proxy forwards the browser's). A web page elsewhere that points its
// own name at this machine (DNS rebinding) sends its own name, to either
// port, so both refuse it.
//
// Usage (in app/): npm run dev   (DEV_USER=someone@example.edu to change who)
import { spawn } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import http from "node:http";

const USER = process.env.DEV_USER ?? "dev@example.edu";
const HOSTS = new Set(["localhost:8787", "127.0.0.1:8787"]);
const REFUSAL = "This development server answers only http://localhost:8787 and http://127.0.0.1:8787.\n";
mkdirSync(".dev", { recursive: true });
writeFileSync(".dev/entry.mjs", [
  "// Written by dev/serve.mjs, for local runs only: the app's Worker, refusing",
  "// a request whose Host is not one the proxy answers to.",
  'import app from "../index.ts";',
  `const HOSTS = new Set(${JSON.stringify([...HOSTS])});`,
  "export default {",
  "  ...app,",
  "  fetch(request, env, ctx) {",
  '    if (!HOSTS.has(request.headers.get("host") ?? "")) {',
  `      return new Response(${JSON.stringify(REFUSAL)}, { status: 403, headers: { "Content-Type": "text/plain; charset=utf-8" } });`,
  "    }",
  "    return app.fetch(request, env, ctx);",
  "  },",
  "};",
  "",
].join("\n"));
writeFileSync(".dev/wrangler.jsonc", JSON.stringify({
  name: "local-app",
  main: "entry.mjs",
  compatibility_date: "2026-10-13",
  compatibility_flags: ["nodejs_compat"],
  d1_databases: [{ binding: "DATA", database_name: "local", database_id: "local" }],
}, null, 2));

const worker = spawn("npx", ["--no-install", "wrangler", "dev", "--config", ".dev/wrangler.jsonc", "--ip", "127.0.0.1", "--port", "8788"], { stdio: "inherit" });
process.on("exit", () => worker.kill());

http.createServer((req, res) => {
  if (!HOSTS.has(req.headers.host ?? "")) {
    res.writeHead(403, { "Content-Type": "text/plain; charset=utf-8" });
    res.end(REFUSAL);
    return;
  }
  const headers = { ...req.headers };
  for (const h of Object.keys(headers)) if (h.startsWith("x-forwarded-")) delete headers[h];
  Object.assign(headers, {
    "x-forwarded-user": USER,
    "x-forwarded-email": USER,
    "x-forwarded-subject": `dev-${USER}`,
    "x-forwarded-groups": "",
    "x-forwarded-host": "localhost:8787",
    "x-forwarded-proto": "http",
  });
  const up = http.request({ host: "127.0.0.1", port: 8788, path: req.url, method: req.method, headers }, (r) => {
    res.writeHead(r.statusCode ?? 502, r.headers);
    r.pipe(res);
  });
  up.on("error", () => { res.writeHead(502); res.end("wrangler dev is not up yet"); });
  req.pipe(up);
}).listen(8787, "127.0.0.1", () => console.log(`http://localhost:8787 (signed in as ${USER})`));
