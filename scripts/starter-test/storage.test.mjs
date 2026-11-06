// The starter's storage route (app/storage.ts, behind app/index.ts) on
// workerd with a local D1. Local D1 is SQLite in a Durable Object, the same
// single-writer shape as production D1, but it does not enforce production's
// 2,000,000-byte limit on a value or a row.
import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";
import { answer, control, person, start, storage } from "./harness.mjs";

describe("the storage route, through the starter's index.ts", () => {
  let w;
  before(async () => { w = await start("index.ts"); });
  after(() => w.stop());

  test("a personal key round trips through set, get, list and delete", async () => {
    assert.deepEqual((await storage(w, { op: "set", key: "note", value: "hello" })).body, { key: "note", value: "hello", shared: false });
    assert.deepEqual((await storage(w, { op: "get", key: "note" })).body, { key: "note", value: "hello", shared: false });
    assert.deepEqual((await storage(w, { op: "list", prefix: "no" })).body, { keys: ["note"], prefix: "no", shared: false });
    assert.deepEqual((await storage(w, { op: "delete", key: "note" })).body, { key: "note", deleted: true, shared: false });
    assert.equal((await storage(w, { op: "get", key: "note" })).body, null);
    assert.deepEqual((await storage(w, { op: "delete", key: "note" })).body, { key: "note", deleted: false, shared: false });
  });

  test("a personal key is the caller's own, and a shared key is everyone's", async () => {
    await storage(w, { op: "set", key: "k", value: "bob's" }, { subject: "bob" });
    await storage(w, { op: "set", key: "k", value: "for all", shared: true }, { subject: "bob" });
    assert.equal((await storage(w, { op: "get", key: "k" }, { subject: "carol" })).body, null);
    assert.equal((await storage(w, { op: "get", key: "k", shared: true }, { subject: "carol" })).body.value, "for all");
    assert.equal((await storage(w, { op: "get", key: "k" }, { subject: "bob" })).body.value, "bob's");
  });

  test("refuses a GET, a request from another site, and a caller with no identity", async () => {
    const get = await answer(await w.fetch("/api/storage", { headers: person("alice") }));
    assert.deepEqual([get.status, get.body], [405, { error: "method_not_allowed" }]);
    const cross = await storage(w, { op: "get", key: "a" }, { headers: { "sec-fetch-site": "cross-site" } });
    assert.deepEqual([cross.status, cross.body], [403, { error: "cross_origin" }]);
    const anonymous = await answer(await w.fetch("/api/storage", {
      method: "POST",
      headers: { "sec-fetch-site": "same-origin", "content-type": "application/json" },
      body: JSON.stringify({ op: "get", key: "a" }),
    }));
    assert.deepEqual([anonymous.status, anonymous.body], [403, { error: "no_signed_in_user" }]);
  });

  test("refuses unreadable JSON, an unknown op, a bad key and a non-string value", async () => {
    const cases = [
      ["{", 400, "bad_request"],
      [JSON.stringify({ op: "rename", key: "a" }), 400, "bad_op"],
      [JSON.stringify({ op: "get", key: "" }), 400, "bad_key"],
      [JSON.stringify({ op: "get", key: "k".repeat(201) }), 400, "bad_key"],
      [JSON.stringify({ op: "set", key: "a", value: 5 }), 400, "bad_value"],
    ];
    for (const [body, status, error] of cases) {
      const r = await storage(w, body, { raw: true });
      assert.deepEqual([r.status, r.body], [status, { error }], body.slice(0, 60));
    }
  });

  test("a list prefix matches literally: % and _ are not wildcards", async () => {
    for (const key of ["abc", "a%c", "a_c"]) await storage(w, { op: "set", key, value: "v" }, { subject: "dave" });
    const list = async (prefix) => (await storage(w, { op: "list", prefix }, { subject: "dave" })).body.keys;
    assert.deepEqual(await list("a%"), ["a%c"]);
    assert.deepEqual(await list("a_"), ["a_c"]);
    assert.deepEqual(await list(""), ["a%c", "a_c", "abc"]);
  });

  test("every storage answer is private to the caller", async () => {
    const r = await storage(w, { op: "get", key: "a" });
    assert.equal(r.headers.get("cache-control"), "private, no-store");
    assert.match(r.headers.get("content-security-policy") ?? "", /default-src 'self'/);
  });
});

describe("the page's Content-Security-Policy", () => {
  let w;
  before(async () => { w = await start("index.ts"); });
  after(() => w.stop());

  // references/html-artifacts.md moves a converted page's inline styles into
  // classes rather than loosening this policy.
  test("allows styles from the app itself only, with no inline styles", async () => {
    const page = await w.fetch("/");
    await page.text();
    const csp = page.headers.get("content-security-policy") ?? "";
    assert.match(csp, /(^|; )style-src 'self'(;|$)/);
    assert.doesNotMatch(csp, /unsafe-inline|style-src-attr|style-src-elem|unsafe-hashes/);
  });
});

describe("the key quota", () => {
  let w;
  before(async () => { w = await start("suite/fault-entry.ts"); });
  after(() => w.stop());

  test("at 1,000 keys a new key is refused and an existing one can still be written", async () => {
    await storage(w, { op: "get", key: "warm" }, { subject: "erin" });
    await control(w, "/__seed?owner=erin&n=999");
    assert.equal((await storage(w, { op: "set", key: "one-more", value: "v" }, { subject: "erin" })).status, 200);
    const over = await storage(w, { op: "set", key: "two-more", value: "v" }, { subject: "erin" });
    assert.deepEqual([over.status, over.body], [400, { error: "too_many_keys" }]);
    assert.equal((await storage(w, { op: "set", key: "seed0000", value: "w" }, { subject: "erin" })).status, 200);
    assert.equal((await control(w, "/__count?owner=erin")).n, 1000);
  });
});

describe("a database fault (R02)", () => {
  test("a failed first CREATE answers 503, with the app's headers", async () => {
    const w = await start("suite/fault-entry.ts");
    try {
      await control(w, "/__fail?sql=CREATE&n=1");
      const first = await storage(w, { op: "get", key: "a" });
      assert.deepEqual([first.status, first.body], [503, { error: "storage_unavailable" }]);
      assert.equal(first.headers.get("x-suite-headers"), "app");
      assert.equal(first.headers.get("cache-control"), "private, no-store");
    } finally {
      await w.stop();
    }
  });

  test("after a failed CREATE the next call tries it again, and one that succeeded is not run again", async () => {
    const w = await start("suite/fault-entry.ts");
    try {
      await control(w, "/__fail?sql=CREATE&n=1");
      await storage(w, { op: "get", key: "a" });
      const next = await storage(w, { op: "set", key: "a", value: "x" });
      assert.deepEqual([next.status, (await control(w, "/__stats")).creates], [200, 2], JSON.stringify(next.body));
      for (let i = 0; i < 3; i++) assert.equal((await storage(w, { op: "get", key: "a" })).body.value, "x");
      assert.equal((await control(w, "/__stats")).creates, 2);
    } finally {
      await w.stop();
    }
  });

  test("calls that arrive together share one CREATE, and each sees its failure", async () => {
    const w = await start("suite/fault-entry.ts");
    try {
      await control(w, "/__fail?sql=CREATE&n=1");
      const together = await (await w.fetch("/__race", {
        method: "POST",
        body: JSON.stringify({ subject: "alice", bodies: [{ op: "get", key: "a" }, { op: "get", key: "b" }] }),
      })).json();
      assert.deepEqual(together, [
        { status: 503, body: { error: "storage_unavailable" } },
        { status: 503, body: { error: "storage_unavailable" } },
      ]);
      assert.equal((await control(w, "/__stats")).creates, 1);
      assert.equal((await storage(w, { op: "get", key: "a" })).status, 200);
      assert.equal((await control(w, "/__stats")).creates, 2);
    } finally {
      await w.stop();
    }
  });

  test("a fault in any later statement answers 503 too, never an unhandled exception", async () => {
    const w = await start("suite/fault-entry.ts");
    try {
      await storage(w, { op: "get", key: "warm" });
      await control(w, "/__fail?sql=INSERT&n=1");
      const failed = await storage(w, { op: "set", key: "a", value: "x" });
      assert.deepEqual([failed.status, failed.body], [503, { error: "storage_unavailable" }]);
      assert.equal((await storage(w, { op: "set", key: "a", value: "x" })).status, 200);
    } finally {
      await w.stop();
    }
  });
});

describe("the value limit, in bytes (R05)", () => {
  let w;
  before(async () => {
    w = await start("suite/fault-entry.ts");
    await storage(w, { op: "get", key: "warm" });
  });
  after(() => w.stop());

  // Production D1 refuses a string or a row over 2,000,000 bytes. Local D1
  // does not, so these show the starter's own check, which must refuse first.
  test("refuses a value over 1,900,000 bytes of UTF-8 before any statement, whatever its length in characters", async () => {
    for (const value of ["漢".repeat(640_000), "\u{1F511}".repeat(475_001)]) {
      await control(w, "/__reset");
      const r = await storage(w, { op: "set", key: "big", value });
      // The status and the reason alone: a whole answer would print the value.
      assert.deepEqual([r.status, r.body?.error], [400, "bad_value"], `${value.length} characters`);
      assert.equal((await control(w, "/__stats")).statements, 0);
    }
  });

  test("stores a value of up to 1,900,000 bytes", async () => {
    for (const value of ["x".repeat(1_900_000), "漢".repeat(633_333)]) {
      const r = await storage(w, { op: "set", key: "big", value });
      assert.deepEqual([r.status, r.body?.error], [200, undefined], `${value.length} characters`);
      assert.equal((await storage(w, { op: "get", key: "big" })).body.value.length, value.length);
    }
  });
});
