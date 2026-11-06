// The starter's local proxy, app/dev/serve.mjs, run as `npm run dev` runs it:
// it starts `wrangler dev` on port 8788 and serves the app on port 8787,
// signed in as DEV_USER. Both ports are fixed, so this file runs on its own
// (scripts/test-starter.sh runs the test files one at a time).
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import http from "node:http";
import { after, before, describe, test } from "node:test";
import { setTimeout as sleep } from "node:timers/promises";
import { APP } from "./harness.mjs";

const PORT = 8787;
const DEV_USER = "owner@example.edu";

/** One request to the proxy at `address`, with `host` as its Host header. */
function request(address, path, { host = `127.0.0.1:${PORT}`, method = "GET", headers = {}, body } = {}) {
  return new Promise((resolve, reject) => {
    const req = http.request({ host: address, port: PORT, path, method, headers: { host, ...headers } }, (res) => {
      let text = "";
      res.setEncoding("utf8");
      res.on("data", (d) => (text += d));
      res.on("end", () => resolve({ status: res.statusCode, text }));
    });
    req.on("error", reject);
    req.end(body);
  });
}

describe("the local proxy, dev/serve.mjs", () => {
  let child;
  let output = "";

  before(async () => {
    child = spawn(process.execPath, ["dev/serve.mjs"], {
      cwd: APP,
      detached: true,
      stdio: ["ignore", "pipe", "pipe"],
      env: { ...process.env, DEV_USER },
    });
    child.stdout.on("data", (d) => (output += d));
    child.stderr.on("data", (d) => (output += d));
    for (let i = 0; i < 120; i++) {
      const up = await request("127.0.0.1", "/healthz").then((r) => r.status === 200, () => false);
      if (up) return;
      await sleep(500);
    }
    throw new Error(`the proxy never answered /healthz:\n${output}`);
  });

  after(async () => {
    // The whole process group: serve.mjs and the wrangler dev it started.
    try { process.kill(-child.pid, "SIGINT"); } catch {}
    await sleep(1500);
    try { process.kill(-child.pid, "SIGKILL"); } catch {}
  });

  test("signs the caller in as DEV_USER", async () => {
    const me = await request("127.0.0.1", "/api/me");
    assert.equal(me.status, 200);
    assert.deepEqual(JSON.parse(me.text), { email: DEV_USER });
  });

  test("serves the storage route, as DEV_USER", async () => {
    const post = (body) => request("127.0.0.1", "/api/storage", {
      method: "POST",
      headers: { "content-type": "application/json", "sec-fetch-site": "same-origin" },
      body: JSON.stringify(body),
    });
    assert.equal((await post({ op: "set", key: "k", value: "v" })).status, 200);
    assert.deepEqual(JSON.parse((await post({ op: "get", key: "k" })).text), { key: "k", value: "v", shared: false });
  });
});
