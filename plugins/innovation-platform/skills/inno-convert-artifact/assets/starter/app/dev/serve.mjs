// Local runs only: serves the app at http://localhost:8787 the way the
// platform's front door would, signed in as a stand-in person. It starts
// `wrangler dev` with a local D1 on port 8788 (config kept in the ignored
// .dev/ directory, since the repository may hold no wrangler config) and a
// small proxy in front that adds the front door's identity headers. Nothing
// here ships: the deployed app's headers come from the real front door.
//
// Usage (in app/): npm run dev   (DEV_USER=someone@example.edu to change who)
import { spawn } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import http from "node:http";

const USER = process.env.DEV_USER ?? "dev@example.edu";
mkdirSync(".dev", { recursive: true });
writeFileSync(".dev/wrangler.jsonc", JSON.stringify({
  name: "local-app",
  main: "../index.ts",
  compatibility_date: "2026-10-13",
  compatibility_flags: ["nodejs_compat"],
  d1_databases: [{ binding: "DATA", database_name: "local", database_id: "local" }],
}, null, 2));

const worker = spawn("npx", ["--no-install", "wrangler", "dev", "--config", ".dev/wrangler.jsonc", "--port", "8788"], { stdio: "inherit" });
process.on("exit", () => worker.kill());

http.createServer((req, res) => {
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
}).listen(8787, () => console.log(`http://localhost:8787 (signed in as ${USER})`));
