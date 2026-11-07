// The starter's local proxy, app/dev/serve.mjs, run as `npm run dev` runs it:
// it starts `wrangler dev` behind it and serves the app signed in as
// DEV_USER. Every run here takes its ports from the operating system
// (DEV_PORT for the proxy, DEV_WORKER_PORT for wrangler dev when a test names
// it), never 8787, so another checkout's suite can run beside this one.
import assert from "node:assert/strict";
import { execFileSync, spawn } from "node:child_process";
import { chmodSync, cpSync, mkdtempSync, readdirSync, symlinkSync, writeFileSync } from "node:fs";
import http from "node:http";
import net from "node:net";
import { networkInterfaces, tmpdir } from "node:os";
import { join } from "node:path";
import { after, before, describe, test } from "node:test";
import { setTimeout as sleep } from "node:timers/promises";
import { APP } from "./harness.mjs";

const DEV_USER = "owner@example.edu";
// What another process answers, as in R02's reproduction.
const OTHER = "OTHER_APP_RESPONSE";

/** A port nothing listens on, from the operating system, other than any in `taken`. */
async function freePort(...taken) {
  for (;;) {
    const port = await new Promise((resolve, reject) => {
      const s = net.createServer().once("error", reject).listen(0, "127.0.0.1", () => {
        const { port } = s.address();
        s.close(() => resolve(port));
      });
    });
    if (!taken.includes(port)) return port;
  }
}

/** Another process on 127.0.0.1:`port`, answering every request as another app. */
function impostor(port) {
  return new Promise((resolve, reject) => {
    const s = http.createServer((req, res) => res.end(OTHER)).once("error", reject);
    s.listen(port, "127.0.0.1", () => resolve(s));
  });
}

/**
 * One request to `address`:`port`, with `host` as its Host header, or with
 * none when `host` is null.
 */
function request(address, path, { port, host = `127.0.0.1:${port}`, method = "GET", headers = {}, body } = {}) {
  return new Promise((resolve, reject) => {
    const options = host === null
      ? { host: address, port, path, method, headers, setHost: false, timeout: 5000 }
      : { host: address, port, path, method, headers: { host, ...headers }, timeout: 5000 };
    const req = http.request(options, (res) => {
      let text = "";
      res.setEncoding("utf8");
      res.on("data", (d) => (text += d));
      res.on("end", () => resolve({ status: res.statusCode, text }));
    });
    req.on("timeout", () => req.destroy(Object.assign(new Error("no answer"), { code: "TIMEOUT" })));
    req.on("error", reject);
    req.end(body);
  });
}

/** Whether anything accepts a connection on 127.0.0.1:`port`. */
function listening(port) {
  return new Promise((resolve) => {
    const s = net.connect(port, "127.0.0.1");
    s.once("connect", () => {
      s.destroy();
      resolve(true);
    });
    s.once("error", () => resolve(false));
  });
}

/** Every process as [pid, parent pid], from ps. */
function processes() {
  return execFileSync("ps", ["-A", "-o", "pid=,ppid="], { encoding: "utf8" })
    .trim()
    .split("\n")
    .map((line) => line.trim().split(/\s+/).map(Number));
}

/** The processes descended from `pid`. */
function descendants(pid) {
  const rows = processes();
  const found = new Set();
  for (let grew = true; grew;) {
    grew = false;
    for (const [p, parent] of rows) {
      if ((parent === pid || found.has(parent)) && !found.has(p)) {
        found.add(p);
        grew = true;
      }
    }
  }
  return [...found];
}

function alive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

/** Waits for `check()` to hold, every 100 ms, for at most `ms`; `what()` names what did not happen. */
async function until(check, ms, what) {
  const end = Date.now() + ms;
  while (!(await check())) {
    if (Date.now() > end) throw new Error(`${what()} (after ${ms / 1000} seconds)`);
    await sleep(100);
  }
}

/** A directory holding an `npx` that runs `script` in sh instead, to put first on PATH. */
function standIn(script) {
  const dir = mkdtempSync(join(tmpdir(), "starter-npx-"));
  writeFileSync(join(dir, "npx"), `#!/bin/sh\n${script}\n`);
  chmodSync(join(dir, "npx"), 0o755);
  return dir;
}

/**
 * Starts dev/serve.mjs in `cwd` with `env` added, and follows it: what it
 * prints, how it exited, and every process it started (`look()` adds the ones
 * running now, since a process whose parent has gone no longer shows as a
 * descendant).
 */
function serve(env = {}, { cwd = APP } = {}) {
  const child = spawn(process.execPath, ["dev/serve.mjs"], {
    cwd,
    detached: true,
    stdio: ["ignore", "pipe", "pipe"],
    env: { ...process.env, DEV_USER, ...env },
  });
  const run = { child, output: "", exit: undefined, seen: new Set() };
  child.stdout.on("data", (d) => (run.output += d));
  child.stderr.on("data", (d) => (run.output += d));
  run.exited = new Promise((resolve) => child.once("exit", (code, signal) => resolve((run.exit = { code, signal }))));
  run.look = () => {
    for (const pid of descendants(child.pid)) run.seen.add(pid);
    return [...run.seen];
  };
  return run;
}

/** Waits for the run's proxy on `port` to answer /healthz as the app. */
async function ready(run, port) {
  await until(
    async () => run.exit !== undefined || (await request("127.0.0.1", "/healthz", { port }).then((r) => r.status === 200 && r.text === "ok", () => false)),
    60_000,
    () => `the proxy never answered /healthz:\n${run.output}`,
  );
  assert.equal(run.exit, undefined, `serve.mjs exited before it was ready:\n${run.output}`);
  run.look();
}

/** The ports the run printed for wrangler dev and its inspector. */
function ports(run) {
  const m = run.output.match(/wrangler dev on 127\.0\.0\.1:(\d+), its inspector on 127\.0\.0\.1:(\d+)/);
  assert.ok(m, `serve.mjs did not print its Worker's ports:\n${run.output}`);
  return { worker: Number(m[1]), inspector: Number(m[2]) };
}

/** Asks the proxy on `port` for a page every 50 ms until the run exits or `ms` pass, and returns each answer. */
async function watch(run, port, ms) {
  const answers = [];
  const end = Date.now() + ms;
  while (run.exit === undefined && Date.now() < end) {
    run.look();
    answers.push(await request("127.0.0.1", "/", { port, host: `localhost:${port}` }).then((r) => `${r.status} ${r.text}`, (e) => e.code));
    await sleep(50);
  }
  return answers;
}

/** Stops a run, whatever its state, with everything it started. */
async function end(run) {
  run.look();
  if (run.exit === undefined) {
    try { process.kill(-run.child.pid, "SIGKILL"); } catch {}
  }
  for (const pid of run.seen) {
    try { process.kill(pid, "SIGKILL"); } catch {}
  }
  await Promise.race([run.exited, sleep(5000)]);
}

/** Whether the run has exited; while it has not, notes the processes it runs. */
function exited(run) {
  if (run.exit === undefined) run.look();
  return run.exit !== undefined;
}

/** Asserts that the run has exited, not with 0, and left no process and no listener on `listeners`. */
async function failedCleanly(run, listeners) {
  await until(() => exited(run), 20_000, () => `serve.mjs still runs:\n${run.output}`);
  assert.notEqual(run.exit.code, 0, `serve.mjs exited 0:\n${run.output}`);
  await until(() => [...run.seen].every((p) => !alive(p)), 5000, () => `left running: ${[...run.seen].filter(alive).join(", ")}`);
  for (const p of listeners) assert.equal(await listening(p), false, `port ${p} still listens`);
}

describe("the local proxy, dev/serve.mjs", () => {
  let run;
  let port;
  let worker;
  let inspector;
  let asked;

  before(async () => {
    port = await freePort();
    asked = await freePort(port);
    run = serve({ DEV_PORT: String(port), DEV_WORKER_PORT: String(asked) });
    await ready(run, port);
    ({ worker, inspector } = ports(run));
  });

  after(() => end(run));

  test("signs the caller in as DEV_USER, on DEV_PORT, with wrangler dev on DEV_WORKER_PORT", async () => {
    const me = await request("127.0.0.1", "/api/me", { port });
    assert.equal(me.status, 200);
    assert.deepEqual(JSON.parse(me.text), { email: DEV_USER });
    assert.match(run.output, new RegExp(`http://localhost:${port}\\b`));
    assert.equal(worker, asked);
  });

  test("listens on the loopback address only, as wrangler dev and its inspector behind it do (R03)", async (t) => {
    const outside = Object.values(networkInterfaces()).flat().filter((a) => a && a.family === "IPv4" && !a.internal);
    // A machine offline has nothing to try; CI always has an address, so there
    // the test may not skip.
    if (outside.length === 0 && !process.env.CI) {
      t.skip("this machine has no address but loopback to try");
      return;
    }
    assert.ok(outside.length > 0, "this machine has no address but loopback to try");
    for (const { address } of outside) {
      for (const p of [port, worker, inspector]) {
        const reached = await request(address, "/healthz", { port: p, host: `${address}:${p}` }).then((r) => `answered ${r.status}`, (e) => e.code);
        assert.equal(reached, "ECONNREFUSED", `${address}:${p}`);
      }
    }
  });

  test("answers only the names localhost:DEV_PORT and 127.0.0.1:DEV_PORT (R03)", async () => {
    for (const host of [`localhost:${port}`, `127.0.0.1:${port}`]) {
      assert.equal((await request("127.0.0.1", "/api/me", { port, host })).status, 200, host);
    }
    // A page whose name was rebound to this machine sends its own name.
    const set = { op: "set", key: "rebound", value: "v" };
    for (const host of [`evil.example:${port}`, "localhost", `localhost:${port}.evil.example`, `127.0.0.1:${worker}`, `localhost:${port + 1}`]) {
      const r = await request("127.0.0.1", "/api/storage", {
        port,
        host,
        method: "POST",
        headers: { "content-type": "application/json", "sec-fetch-site": "same-origin" },
        body: JSON.stringify(set),
      });
      assert.equal(r.status, 403, host);
    }
    const none = await request("127.0.0.1", "/api/me", { port, host: null });
    assert.ok(none.status === 400 || none.status === 403, `no Host: answered ${none.status}`);
    const get = await request("127.0.0.1", "/api/storage", {
      port,
      method: "POST",
      headers: { "content-type": "application/json", "sec-fetch-site": "same-origin" },
      body: JSON.stringify({ op: "get", key: "rebound" }),
    });
    assert.equal(JSON.parse(get.text), null, "a refused request reached the app");
  });

  // wrangler dev passes the Host it was sent through to the Worker, and the
  // Worker trusts X-Forwarded-*, so a page rebound to this machine could
  // otherwise skip the proxy and name any identity it likes on wrangler
  // dev's port.
  test("refuses a request straight to wrangler dev's port under any other name, forged identity and all (R03)", async () => {
    const forged = {
      "content-type": "application/json",
      "sec-fetch-site": "same-origin",
      "x-forwarded-user": DEV_USER,
      "x-forwarded-subject": `dev-${DEV_USER}`,
    };
    for (const host of [`evil.example:${worker}`, `evil.example:${port}`, `127.0.0.1:${worker}`, `localhost:${worker}`]) {
      const set = await request("127.0.0.1", "/api/storage", {
        port: worker,
        host,
        method: "POST",
        headers: forged,
        body: JSON.stringify({ op: "set", key: "planted", value: "from a rebound page" }),
      });
      assert.equal(set.status, 403, `set on ${worker} as ${host}: ${set.text.slice(0, 80)}`);
      const me = await request("127.0.0.1", "/api/me", { port: worker, host, headers: forged });
      assert.equal(me.status, 403, `/api/me on ${worker} as ${host}: ${me.text.slice(0, 80)}`);
    }
    const get = await request("127.0.0.1", "/api/storage", {
      port,
      method: "POST",
      headers: { "content-type": "application/json", "sec-fetch-site": "same-origin" },
      body: JSON.stringify({ op: "get", key: "planted" }),
    });
    assert.equal(JSON.parse(get.text), null, "a request straight to wrangler dev's port wrote DEV_USER's data");
  });

  test("serves the storage route, as DEV_USER", async () => {
    const post = (body) => request("127.0.0.1", "/api/storage", {
      port,
      method: "POST",
      headers: { "content-type": "application/json", "sec-fetch-site": "same-origin" },
      body: JSON.stringify(body),
    });
    assert.equal((await post({ op: "set", key: "k", value: "v" })).status, 200);
    assert.deepEqual(JSON.parse((await post({ op: "get", key: "k" })).text), { key: "k", value: "v", shared: false });
  });
});

describe("the proxy lives as long as its own Worker, and serves no other (R02)", () => {
  for (const signal of ["SIGINT", "SIGTERM"]) {
    test(`${signal} closes the proxy and stops everything serve.mjs started`, async () => {
      const port = await freePort();
      const run = serve({ DEV_PORT: String(port) });
      try {
        await ready(run, port);
        const { worker, inspector } = ports(run);
        const started = run.look();
        assert.ok(started.length > 0, "serve.mjs started no process");
        process.kill(run.child.pid, signal);
        await until(() => run.exit !== undefined, 15_000, () => `serve.mjs still runs after ${signal}:\n${run.output}`);
        assert.equal(run.exit.code, 0, run.output);
        await until(() => started.every((p) => !alive(p)), 5000, () => `left running: ${started.filter(alive).join(", ")}`);
        for (const p of [port, worker, inspector]) assert.equal(await listening(p), false, `port ${p} still listens`);
      } finally {
        await end(run);
      }
    });
  }

  test("when wrangler dev exits, the proxy closes, serve.mjs exits non-zero, and nothing it started stays", async () => {
    const port = await freePort();
    const run = serve({ DEV_PORT: String(port) });
    try {
      await ready(run, port);
      const { worker, inspector } = ports(run);
      const own = processes().filter(([, parent]) => parent === run.child.pid).map(([pid]) => pid);
      assert.equal(own.length, 1, `serve.mjs has ${own.length} children`);
      // Killed outright, as a crash would end it: wrangler dev and workerd,
      // below it, are then left without it.
      process.kill(own[0], "SIGKILL");
      await failedCleanly(run, [port, worker, inspector]);
      assert.match(run.output, /wrangler dev stopped/);
    } finally {
      await end(run);
    }
  });

  test("a Worker that exits at once fails startup, and the proxy never serves the process on its port (the reproduction)", async () => {
    const port = await freePort();
    const workerPort = await freePort(port);
    const other = await impostor(workerPort);
    const run = serve({ DEV_PORT: String(port), DEV_WORKER_PORT: String(workerPort), PATH: `${standIn("exit 23")}:${process.env.PATH}` });
    try {
      const answers = await watch(run, port, 30_000);
      await failedCleanly(run, [port]);
      assert.ok(!answers.some((a) => String(a).includes(OTHER)), `the proxy served the other process: ${answers.join(" | ")}`);
    } finally {
      await end(run);
      other.close();
    }
  });

  test("a wrangler dev that cannot be spawned fails startup", async () => {
    const port = await freePort();
    const run = serve({ DEV_PORT: String(port), PATH: mkdtempSync(join(tmpdir(), "starter-empty-")) });
    try {
      await failedCleanly(run, [port]);
      assert.match(run.output, /could not start wrangler dev/);
    } finally {
      await end(run);
    }
  });

  test("a Worker port another process holds fails startup with the real wrangler dev, and the proxy never serves that process", async () => {
    const port = await freePort();
    const workerPort = await freePort(port);
    const other = await impostor(workerPort);
    const run = serve({ DEV_PORT: String(port), DEV_WORKER_PORT: String(workerPort) });
    try {
      const answers = await watch(run, port, 60_000);
      await failedCleanly(run, [port]);
      assert.ok(!answers.some((a) => String(a).includes(OTHER)), `the proxy served the other process: ${answers.join(" | ")}`);
      assert.equal((await request("127.0.0.1", "/", { port: workerPort })).text, OTHER, "the other process was disturbed");
    } finally {
      await end(run);
      other.close();
    }
  });

  // A wrangler dev still starting (here one that never does) while another
  // process answers its port: only the instance check tells them apart.
  test("a process answering the Worker's port that is not this run's Worker is never served, and fails startup", async () => {
    const port = await freePort();
    const workerPort = await freePort(port);
    const other = await impostor(workerPort);
    const run = serve({ DEV_PORT: String(port), DEV_WORKER_PORT: String(workerPort), PATH: `${standIn("exec sleep 600")}:${process.env.PATH}` });
    try {
      const answers = await watch(run, port, 70_000);
      await failedCleanly(run, [port]);
      assert.ok(!answers.some((a) => String(a).includes(OTHER)), `the proxy served the other process: ${answers.join(" | ")}`);
      assert.match(run.output, /not this run's Worker/);
    } finally {
      await end(run);
      other.close();
    }
  });

  test("a proxy port in use fails startup at once, starting nothing", async () => {
    const port = await freePort();
    const other = await impostor(port);
    const run = serve({ DEV_PORT: String(port) });
    try {
      await until(() => exited(run), 10_000, () => `serve.mjs still runs:\n${run.output}`);
      assert.notEqual(run.exit.code, 0, run.output);
      assert.match(run.output, /DEV_PORT/);
      assert.deepEqual([...run.seen].filter(alive), []);
      assert.equal((await request("127.0.0.1", "/", { port })).text, OTHER, "the other process was disturbed");
    } finally {
      await end(run);
      other.close();
    }
  });

  test("two checkouts run at once, each proxy on its own Worker and its own data", async () => {
    const second = mkdtempSync(join(tmpdir(), "starter-second-"));
    for (const name of readdirSync(APP)) {
      if (name === "node_modules") symlinkSync(join(APP, name), join(second, name));
      else if (name !== ".dev" && name !== ".wrangler") cpSync(join(APP, name), join(second, name), { recursive: true });
    }
    const a = await freePort();
    const b = await freePort(a);
    const one = serve({ DEV_PORT: String(a), DEV_USER: "one@example.edu" });
    const two = serve({ DEV_PORT: String(b), DEV_USER: "two@example.edu" }, { cwd: second });
    try {
      await Promise.all([ready(one, a), ready(two, b)]);
      assert.notEqual(ports(one).worker, ports(two).worker);
      const post = (port, body) => request("127.0.0.1", "/api/storage", {
        port,
        method: "POST",
        headers: { "content-type": "application/json", "sec-fetch-site": "same-origin" },
        body: JSON.stringify(body),
      }).then((r) => JSON.parse(r.text));
      assert.deepEqual(JSON.parse((await request("127.0.0.1", "/api/me", { port: a })).text), { email: "one@example.edu" });
      assert.deepEqual(JSON.parse((await request("127.0.0.1", "/api/me", { port: b })).text), { email: "two@example.edu" });
      await post(a, { op: "set", key: "where", value: "one", shared: true });
      assert.equal((await post(a, { op: "get", key: "where", shared: true })).value, "one");
      assert.equal(await post(b, { op: "get", key: "where", shared: true }), null, "the second checkout read the first one's data");
    } finally {
      await Promise.all([end(one), end(two)]);
    }
  });
});
