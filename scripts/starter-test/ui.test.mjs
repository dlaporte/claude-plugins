// The starter's interface as dev/build-ui.mjs builds it and the Worker serves
// it (UI_SCRIPT in .ui-build/ui.ts), run in a DOM (jsdom) with each fetch
// answered by the test: what the app bar says (PL-12), and what a person sees
// and can do while a request is under way, when it fails and when the
// session has ended (R11). The last case runs the page against the starter's
// own Worker instead.
//
// jsdom runs no module script, so the page's script, an ES module with no
// import or export, runs as a classic one. A timer of a second or more (the
// shim's deadline) never fires by itself: page.expire() fires the pending
// ones and returns their delays.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, describe, test } from "node:test";
import { setTimeout as sleep } from "node:timers/promises";
import { JSDOM } from "jsdom";
import { APP, person, start } from "./harness.mjs";

const UI_SCRIPT = (() => {
  const lead = "export const UI_SCRIPT = ";
  const line = readFileSync(join(APP, ".ui-build/ui.ts"), "utf8").split("\n").find((l) => l.startsWith(lead));
  return JSON.parse(line.slice(lead.length, -1));
})();

const EMAIL = "alice@example.edu";
const DEADLINE = 30_000;

// Answers a test gives.
const ok = (body) => Promise.resolve(Response.json(body));
const answer = (status, body) => Promise.resolve(body === undefined ? new Response("Sign in again.", { status }) : Response.json(body, { status }));
const offline = () => Promise.reject(new TypeError("Failed to fetch"));
const never = () => new Promise(() => {});
const count = (value, shared = false) => ok({ key: "count", value: String(value), shared });

/** An answer the test gives later, with give(). */
function held() {
  let give;
  const promise = new Promise((resolve) => (give = resolve));
  return { promise, give };
}

/** The app's routes: /api/me answered by `me`, /api/storage by `storage`. */
function app({ me = () => ok({ email: EMAIL }), storage = () => ok(null) } = {}) {
  return (call) => (call.path === "/api/me" ? me(call) : storage(call));
}

const pages = [];
afterEach(() => {
  while (pages.length) pages.pop().window.close();
});

/**
 * Opens the page with `route(call)` answering each fetch; a call is
 * { path, method, op, body, init, signal }, with op and body read from a
 * storage call's JSON.
 */
function open(route) {
  const { window } = new JSDOM('<!doctype html><html lang="en"><body><div id="root"></div></body></html>', {
    url: "http://localhost:8787/notes?view=all",
    runScripts: "outside-only",
    pretendToBeVisual: true,
  });
  const page = { window, document: window.document, calls: [], deadlines: new Map() };
  const setTimer = window.setTimeout.bind(window);
  const clearTimer = window.clearTimeout.bind(window);
  let id = 1_000_000;
  window.setTimeout = (fn, ms = 0, ...args) => {
    if (ms < 1000) return setTimer(fn, ms, ...args);
    page.deadlines.set(++id, { ms, fire: () => fn(...args) });
    return id;
  };
  window.clearTimeout = (t) => {
    if (!page.deadlines.delete(t)) clearTimer(t);
  };
  page.expire = () => {
    const due = [...page.deadlines.values()];
    page.deadlines.clear();
    for (const d of due) d.fire();
    return due.map((d) => d.ms);
  };
  window.fetch = (input, init = {}) => {
    const body = typeof init.body === "string" ? JSON.parse(init.body) : undefined;
    const call = { path: String(input), method: init.method ?? "GET", op: body?.op, body, init, signal: init.signal };
    page.calls.push(call);
    return route(call);
  };
  window.eval(`"use strict";${UI_SCRIPT}`);
  pages.push(page);
  return page;
}

const text = (el) => (el?.textContent ?? "").replace(/\s+/g, " ").trim();
const bar = (page) => page.document.querySelector("header");
const mine = (page) => page.document.querySelectorAll("main section > div")[0];
const everyone = (page) => page.document.querySelectorAll("main section > div")[1];
const loaded = (page) => control(mine(page), "Mine:") && control(everyone(page), "Everyone:");
const control = (root, name) => [...(root?.querySelectorAll("button, a") ?? [])].find((el) => text(el).startsWith(name));
const status = (root) => text(root?.querySelector('[role="status"]'));
const alert = (root) => text(root?.querySelector('[role="alert"]'));
const storageCalls = (page, op, key = "count") => page.calls.filter((c) => c.op === op && c.body.key === key);

/** Waits for `check()` to hold, for at most `ms`; `what` names what did not happen. */
async function until(check, what, ms = 5000) {
  const end = Date.now() + ms;
  while (!check()) {
    if (Date.now() > end) throw new Error(`no ${what} after ${ms} ms`);
    await sleep(10);
  }
}

/** The fields of a RequestError a page acts on. */
const failure = (e) => ({ name: e?.name, kind: e?.kind, status: e?.status, reason: e?.reason, outcomeUnknown: e?.outcomeUnknown });

describe("the app bar (PL-12, R11)", () => {
  test("names the signed-in person after the words Signed in as, which only a screen reader reads, beside the sign-out link", async () => {
    const page = open(app());
    await until(() => text(bar(page)).includes(EMAIL), "address in the bar");
    assert.match(text(bar(page)), new RegExp(`Signed in as ${EMAIL}`));
    assert.ok([...bar(page).querySelectorAll(".sr-only")].some((el) => text(el) === "Signed in as"), "Signed in as is not for screen readers only");
    assert.equal(control(bar(page), "Sign out")?.getAttribute("href"), "/_auth/signout");
  });

  for (const [name, fail] of [["a 503", () => answer(503, { error: "unavailable" })], ["a network failure", offline]]) {
    test(`a failed read of /api/me (${name}) is shown, with Try again, and the sign-out link stays`, async () => {
      let me = fail;
      const page = open(app({ me: (c) => me(c) }));
      await until(() => status(bar(page)).startsWith("Could not check who is signed in."), "failure in the bar");
      assert.ok(!text(bar(page)).includes("@"), "the bar shows an address it could not read");
      assert.equal(control(bar(page), "Sign out")?.getAttribute("href"), "/_auth/signout");
      me = () => ok({ email: EMAIL });
      control(bar(page), "Try again").click();
      await until(() => text(bar(page)).includes(`Signed in as ${EMAIL}`), "address after Try again");
      assert.equal(status(bar(page)), "");
      assert.equal(page.calls.filter((c) => c.path === "/api/me").length, 2, "/api/me was read again by itself");
    });
  }

  test("a 401 from /api/me says the session has ended, with a link that loads this page again to sign in", async () => {
    const page = open(app({ me: () => answer(401) }));
    await until(() => status(bar(page)).includes("session has ended"), "session end in the bar");
    const link = control(bar(page), "Sign in again");
    assert.equal(link?.tagName, "A");
    assert.equal(link.href, page.window.location.href);
    assert.equal(control(bar(page), "Sign out"), undefined);
  });

  test("a /api/me that never answers is given up at the 30-second deadline, and shown", async () => {
    const page = open(app({ me: never, storage: () => count(0) }));
    await until(() => loaded(page), "counts");
    assert.equal(status(bar(page)), "");
    assert.deepEqual(page.expire(), [DEADLINE]);
    await until(() => status(bar(page)).includes("took too long"), "deadline in the bar");
    assert.ok(control(bar(page), "Try again"));
  });

  test("a storage call answered with 401 tells the bar the session has ended", async () => {
    const page = open(app({ storage: () => answer(401) }));
    await until(() => status(bar(page)).includes("session has ended"), "session end in the bar");
    assert.equal(control(bar(page), "Sign in again")?.href, page.window.location.href);
  });
});

describe("window.storage, the shim (R11)", () => {
  test("a call that never answers settles at the 30-second deadline, aborted and never sent again; a write's outcome is then unknown", async () => {
    const page = open(app({ storage: (c) => (c.body.key === "probe" ? never() : ok(null)) }));
    await until(() => loaded(page), "counts");
    let settled = 0;
    const get = page.window.storage.get("probe").then(() => "answered", (e) => e).finally(() => settled++);
    const set = page.window.storage.set("probe", "v").then(() => "answered", (e) => e).finally(() => settled++);
    await sleep(50);
    assert.equal(settled, 0, "a call settled before its deadline");
    assert.deepEqual(page.expire(), [DEADLINE, DEADLINE]);
    assert.deepEqual(failure(await get), { name: "RequestError", kind: "timeout", status: null, reason: null, outcomeUnknown: false });
    assert.deepEqual(failure(await set), { name: "RequestError", kind: "timeout", status: null, reason: null, outcomeUnknown: true });
    await sleep(100);
    const probes = page.calls.filter((c) => c.body?.key === "probe");
    assert.deepEqual(probes.map((c) => c.op), ["get", "set"], "a call was sent again");
    assert.ok(probes.every((c) => c.signal?.aborted), "a timed-out request was not aborted");
  });

  const cases = [
    ["401", () => answer(401), { kind: "signed_out", status: 401, reason: null }, false],
    ["403 no_signed_in_user", () => answer(403, { error: "no_signed_in_user" }), { kind: "refused", status: 403, reason: "no_signed_in_user" }, false],
    ["400 too_many_keys", () => answer(400, { error: "too_many_keys" }), { kind: "refused", status: 400, reason: "too_many_keys" }, false],
    ["429", () => answer(429, {}), { kind: "unavailable", status: 429, reason: null }, false],
    ["503 storage_unavailable", () => answer(503, { error: "storage_unavailable" }), { kind: "unavailable", status: 503, reason: "storage_unavailable" }, true],
    ["a network failure", offline, { kind: "network", status: null, reason: null }, true],
  ];
  for (const [name, give, expected, lostWrite] of cases) {
    test(`${name} fails each call with its kind and a sentence, sent once; a write's outcome is unknown only when its answer was lost`, async () => {
      const page = open(app({ storage: (c) => (c.body.key === "probe" ? give() : ok(null)) }));
      for (const [op, args, write] of [["get", ["probe"], false], ["set", ["probe", "v"], true], ["delete", ["probe", true], true]]) {
        const e = await page.window.storage[op](...args).then(() => undefined, (x) => x);
        assert.deepEqual(failure(e), { name: "RequestError", ...expected, outcomeUnknown: write && lostWrite }, op);
        assert.match(e.message, /^[A-Z].*\.$/, `${op}: ${e.message}`);
      }
      await sleep(50);
      assert.deepEqual(page.calls.filter((c) => c.body?.key === "probe").map((c) => c.op), ["get", "set", "delete"], "a call was sent again");
    });
  }
});

describe("the placeholder artifact's states (R11)", () => {
  for (const [name, fail, expire] of [["a 503", () => answer(503, { error: "storage_unavailable" }), false], ["a network failure", offline, false], ["the deadline", never, true]]) {
    test(`the first read shows it is loading, and a failed one (${name}) says so, with Try again, never as a count of zero`, async () => {
      const first = held();
      let read = () => first.promise;
      const page = open(app({ storage: (c) => (c.op === "get" && !c.body.shared ? read() : ok(null)) }));
      await until(() => status(mine(page)) === "Loading the count.", "loading status");
      assert.equal(control(mine(page), "Mine:"), undefined, "a count shows before it was read");
      if (expire) {
        page.expire();
      } else {
        first.give(fail());
      }
      await until(() => alert(mine(page)).startsWith("Could not load the count."), "read failure");
      assert.ok(!/Mine: \d/.test(text(mine(page))), `a failed read shows a count: ${text(mine(page))}`);
      assert.equal(status(mine(page)), "");
      read = () => count(4);
      control(mine(page), "Try again").click();
      await until(() => text(control(mine(page), "Mine:")) === "Mine: 4", "count after Try again");
      assert.equal(alert(mine(page)), "");
    });
  }

  test("a read answered with 401 says the session has ended, with a link that loads this page again", async () => {
    const page = open(app({ storage: (c) => (c.op === "get" && !c.body.shared ? answer(401) : ok(null)) }));
    await until(() => alert(mine(page)).includes("session has ended"), "session end");
    assert.equal(control(mine(page), "Sign in again")?.href, page.window.location.href);
    assert.equal(control(mine(page), "Try again"), undefined);
  });

  test("a save in flight disables its button, and clicks meanwhile send nothing more (no lost increments)", async () => {
    const saves = [held()];
    const page = open(app({ storage: (c) => (c.op === "set" ? saves[saves.length - 1].promise : count(1, c.body.shared)) }));
    await until(() => control(mine(page), "Mine:"), "count");
    const button = control(mine(page), "Mine:");
    button.click();
    button.click();
    button.click();
    await until(() => status(mine(page)) === "Saving.", "saving status");
    assert.equal(button.disabled, true);
    assert.deepEqual(storageCalls(page, "set").map((c) => c.body.value), ["2"]);
    saves[0].give(Response.json({ key: "count", value: "2", shared: false }));
    await until(() => text(button) === "Mine: 2" && !button.disabled, "saved count");
    saves.push(held());
    button.click();
    saves[1].give(Response.json({ key: "count", value: "3", shared: false }));
    await until(() => text(button) === "Mine: 3", "second save");
    assert.deepEqual(storageCalls(page, "set").map((c) => c.body.value), ["2", "3"]);
  });

  for (const [name, fail, expire] of [["a 503", () => answer(503, { error: "storage_unavailable" }), false], ["a network failure", offline, false], ["the deadline", never, true]]) {
    test(`a save whose answer was lost (${name}) says it may have been saved, and offers to read the count again, never sending it again`, async () => {
      let read = () => count(1);
      const page = open(app({ storage: (c) => (c.op === "set" ? fail() : c.body.shared ? count(0, true) : read()) }));
      await until(() => control(mine(page), "Mine:"), "count");
      control(mine(page), "Mine:").click();
      if (expire) {
        await until(() => status(mine(page)) === "Saving.", "saving status");
        page.expire();
      }
      await until(() => alert(mine(page)).includes("may have been saved"), "lost save");
      await sleep(100);
      assert.equal(storageCalls(page, "set").length, 1, "the save was sent again");
      const gets = storageCalls(page, "get").filter((c) => !c.body.shared).length;
      read = () => count(2);
      control(mine(page), "Check the count").click();
      await until(() => text(control(mine(page), "Mine:")) === "Mine: 2", "count read again");
      assert.equal(storageCalls(page, "get").filter((c) => !c.body.shared).length, gets + 1);
      assert.equal(storageCalls(page, "set").length, 1);
      assert.equal(alert(mine(page)), "");
    });
  }

  test("a refused save says it was not saved, and why, and leaves the count and its button as they were", async () => {
    const page = open(app({ storage: (c) => (c.op === "set" ? answer(400, { error: "too_many_keys" }) : count(1, c.body.shared)) }));
    await until(() => control(mine(page), "Mine:"), "count");
    control(mine(page), "Mine:").click();
    await until(() => alert(mine(page)).startsWith("Not saved."), "refusal");
    assert.match(alert(mine(page)), /too_many_keys/);
    assert.equal(text(control(mine(page), "Mine:")), "Mine: 1");
    assert.equal(control(mine(page), "Mine:").disabled, false);
    assert.equal(control(mine(page), "Check the count"), undefined);
  });
});

describe("the page against the starter's own Worker", () => {
  test("signs in, reads, saves and reads back each person's count and the shared one through the storage route", async () => {
    const w = await start("index.ts");
    try {
      const as = (subject) => (c) => {
        const headers = new Headers(c.init.headers);
        for (const [name, value] of Object.entries(person(subject))) headers.set(name, value);
        return w.fetch(c.path, { method: c.method, headers, body: c.init.body });
      };
      const first = open(as("alice"));
      await until(() => text(bar(first)).includes("Signed in as alice@example.edu"), "address", 15_000);
      await until(() => control(mine(first), "Mine: 0"), "count", 15_000);
      control(mine(first), "Mine:").click();
      await until(() => control(mine(first), "Mine: 1") && !control(mine(first), "Mine:").disabled, "saved count", 15_000);
      control(everyone(first), "Everyone:").click();
      await until(() => control(everyone(first), "Everyone: 1"), "shared count", 15_000);
      const again = open(as("alice"));
      await until(() => control(mine(again), "Mine: 1"), "count read back", 15_000);
      const bob = open(as("bob"));
      await until(() => control(mine(bob), "Mine: 0") && control(everyone(bob), "Everyone: 1"), "bob's counts", 15_000);
    } finally {
      await w.stop();
    }
  });
});
