// Local runs only: serves the app at http://localhost:8787 the way the
// platform's front door would, signed in as a stand-in person. It starts
// `wrangler dev` with a local D1 on port 8788 (config kept in the ignored
// .dev/ directory, since the repository may hold no wrangler config) and a
// small proxy in front that adds the front door's identity headers. Nothing
// here ships: the deployed app's headers come from the real front door.
//
// Both answer this machine only, since anyone the proxy answers is signed in
// as DEV_USER: wrangler dev and the proxy both listen on 127.0.0.1, and the
// proxy also refuses (403) a request whose Host is not localhost:8787 or
// 127.0.0.1:8787. A web page elsewhere that points its own name at this
// machine (DNS rebinding) sends its own name, so it is refused too.
//
// Usage (in app/): npm run dev   (DEV_USER=someone@example.edu to change who)
import { spawn } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import http from "node:http";

const USER = process.env.DEV_USER ?? "dev@example.edu";
const HOSTS = new Set(["localhost:8787", "127.0.0.1:8787"]);
mkdirSync(".dev", { recursive: true });
writeFileSync(".dev/wrangler.jsonc", JSON.stringify({
  name: "local-app",
  main: "../index.ts",
  compatibility_date: "2026-10-13",
  compatibility_flags: ["nodejs_compat"],
  d1_databases: [{ binding: "DATA", database_name: "local", database_id: "local" }],
}, null, 2));

const worker = spawn("npx", ["--no-install", "wrangler", "dev", "--config", ".dev/wrangler.jsonc", "--ip", "127.0.0.1", "--port", "8788"], { stdio: "inherit" });
process.on("exit", () => worker.kill());

http.createServer((req, res) => {
  if (!HOSTS.has(req.headers.host ?? "")) {
    res.writeHead(403, { "Content-Type": "text/plain; charset=utf-8" });
    res.end("This development server answers only http://localhost:8787 and http://127.0.0.1:8787.\n");
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
