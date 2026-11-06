// The starter's local proxy, app/dev/serve.mjs, run as `npm run dev` runs it:
// it starts `wrangler dev` on port 8788 and serves the app on port 8787,
// signed in as DEV_USER. Both ports are fixed, so this file runs on its own
// (scripts/test-starter.sh runs the test files one at a time).
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import http from "node:http";
import { networkInterfaces } from "node:os";
import { after, before, describe, test } from "node:test";
import { setTimeout as sleep } from "node:timers/promises";
import { APP } from "./harness.mjs";

const PORT = 8787;
const DEV_USER = "owner@example.edu";

/**
 * One request to the proxy at `address`, with `host` as its Host header, or
 * with none when `host` is null.
 */
function request(address, path, { port = PORT, host = `127.0.0.1:${port}`, method = "GET", headers = {}, body } = {}) {
  return new Promise((resolve, reject) => {
    const options = host === null
      ? { host: address, port, path, method, headers, setHost: false }
      : { host: address, port, path, method, headers: { host, ...headers } };
    const req = http.request(options, (res) => {
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

  test("listens on the loopback address only, as wrangler dev behind it does (R03)", async (t) => {
    const outside = Object.values(networkInterfaces()).flat().filter((a) => a && a.family === "IPv4" && !a.internal);
    // A machine offline has nothing to try; CI always has an address, so there
    // the test may not skip.
    if (outside.length === 0 && !process.env.CI) {
      t.skip("this machine has no address but loopback to try");
      return;
    }
    assert.ok(outside.length > 0, "this machine has no address but loopback to try");
    for (const { address } of outside) {
      for (const port of [PORT, 8788]) {
        const reached = await request(address, "/healthz", { port, host: `${address}:${port}` }).then((r) => `answered ${r.status}`, (e) => e.code);
        assert.equal(reached, "ECONNREFUSED", `${address}:${port}`);
      }
    }
  });

  test("answers only the names localhost:8787 and 127.0.0.1:8787 (R03)", async () => {
    for (const host of [`localhost:${PORT}`, `127.0.0.1:${PORT}`]) {
      assert.equal((await request("127.0.0.1", "/api/me", { host })).status, 200, host);
    }
    // A page whose name was rebound to this machine sends its own name.
    const set = { op: "set", key: "rebound", value: "v" };
    for (const host of [`evil.example:${PORT}`, "localhost", `localhost:${PORT}.evil.example`, `127.0.0.1:8788`]) {
      const r = await request("127.0.0.1", "/api/storage", {
        host,
        method: "POST",
        headers: { "content-type": "application/json", "sec-fetch-site": "same-origin" },
        body: JSON.stringify(set),
      });
      assert.equal(r.status, 403, host);
    }
    const none = await request("127.0.0.1", "/api/me", { host: null });
    assert.ok(none.status === 400 || none.status === 403, `no Host: answered ${none.status}`);
    const get = await request("127.0.0.1", "/api/storage", {
      method: "POST",
      headers: { "content-type": "application/json", "sec-fetch-site": "same-origin" },
      body: JSON.stringify({ op: "get", key: "rebound" }),
    });
    assert.equal(JSON.parse(get.text), null, "a refused request reached the app");
  });

  // wrangler dev passes the Host it was sent through to the Worker, and the
  // Worker trusts X-Forwarded-*, so a page rebound to this machine could
  // otherwise skip the proxy and name any identity it likes on port 8788.
  test("refuses a request straight to wrangler dev's port under any other name, forged identity and all (R03)", async () => {
    const forged = {
      "content-type": "application/json",
      "sec-fetch-site": "same-origin",
      "x-forwarded-user": DEV_USER,
      "x-forwarded-subject": `dev-${DEV_USER}`,
    };
    for (const host of ["evil.example:8788", `evil.example:${PORT}`, "127.0.0.1:8788", "localhost:8788"]) {
      const set = await request("127.0.0.1", "/api/storage", {
        port: 8788,
        host,
        method: "POST",
        headers: forged,
        body: JSON.stringify({ op: "set", key: "planted", value: "from a rebound page" }),
      });
      assert.equal(set.status, 403, `set on 8788 as ${host}: ${set.text.slice(0, 80)}`);
      const me = await request("127.0.0.1", "/api/me", { port: 8788, host, headers: forged });
      assert.equal(me.status, 403, `/api/me on 8788 as ${host}: ${me.text.slice(0, 80)}`);
    }
    const get = await request("127.0.0.1", "/api/storage", {
      method: "POST",
      headers: { "content-type": "application/json", "sec-fetch-site": "same-origin" },
      body: JSON.stringify({ op: "get", key: "planted" }),
    });
    assert.equal(JSON.parse(get.text), null, "a request straight to 8788 wrote DEV_USER's data");
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
