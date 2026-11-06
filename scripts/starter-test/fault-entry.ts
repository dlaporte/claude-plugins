// A test entry: the starter's real handleStorage (../storage.ts) behind a D1
// binding that counts the statements it runs and fails one on demand, plus a
// few routes the tests use to set up and read the database. Everything else
// is the real local D1. Only the suite starts it (harness.mjs); it never ships.
import { currentUser } from "../identity";
import { handleStorage } from "../storage";

interface Env {
  DATA: D1Database;
}

// The headers the starter passes as its security headers, so a test can see
// that an answer carries the app's own.
const APP_HEADERS = { "X-Suite-Headers": "app" };

let creates = 0;
let statements = 0;
let fail = { prefix: "", remaining: 0 };

function counted(stmt: D1PreparedStatement, sql: string): D1PreparedStatement {
  return new Proxy(stmt, {
    get(target, prop) {
      if (prop === "bind") return (...values: unknown[]) => counted(target.bind(...values), sql);
      if (prop === "run" || prop === "first" || prop === "all" || prop === "raw") {
        return async (...args: unknown[]) => {
          statements++;
          if (sql.startsWith("CREATE")) creates++;
          if (fail.remaining > 0 && sql.startsWith(fail.prefix)) {
            fail.remaining--;
            // A lost connection fails after a while, not at once, so calls
            // that arrive meanwhile meet the same attempt. The text is D1's
            // own for a transient fault, which it does not retry on a write.
            await new Promise((resolve) => setTimeout(resolve, 50));
            throw new Error("D1_ERROR: Network connection lost.");
          }
          return (target[prop] as (...a: unknown[]) => unknown)(...args);
        };
      }
      const value = Reflect.get(target, prop);
      return typeof value === "function" ? value.bind(target) : value;
    },
  });
}

function wrap(db: D1Database): D1Database {
  return new Proxy(db, {
    get(target, prop) {
      if (prop === "prepare") return (sql: string) => counted(target.prepare(sql), sql);
      const value = Reflect.get(target, prop);
      return typeof value === "function" ? value.bind(target) : value;
    },
  });
}

async function call(request: Request, env: Env): Promise<Response> {
  try {
    return await handleStorage(request, { DATA: wrap(env.DATA) }, currentUser(request.headers), APP_HEADERS);
  } catch (e) {
    // What would reach the runtime as an unhandled exception, named so a
    // failing test shows it.
    return Response.json({ uncaught: String((e as Error).message) }, { status: 500 });
  }
}

function identity(subject: string): Record<string, string> {
  return {
    "x-forwarded-user": `${subject}@example.edu`,
    "x-forwarded-subject": subject,
    "sec-fetch-site": "same-origin",
    "content-type": "application/json",
  };
}

function storageRequest(subject: string, body: unknown): Request {
  return new Request("http://app.test/api/storage", { method: "POST", headers: identity(subject), body: JSON.stringify(body) });
}

async function summary(r: Response): Promise<{ status: number; body: unknown; appHeaders: string | null }> {
  return { status: r.status, body: await r.json(), appHeaders: r.headers.get("x-suite-headers") };
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const q = (name: string) => url.searchParams.get(name) ?? "";
    switch (url.pathname) {
      case "/__fail":
        fail = { prefix: q("sql"), remaining: Number(q("n") || 1) };
        return Response.json({ ok: true });
      case "/__stats":
        return Response.json({ creates, statements });
      case "/__reset":
        creates = 0;
        statements = 0;
        return Response.json({ ok: true });
      case "/__seed": {
        // n keys named seed0000 and on, straight into the table (which a
        // storage call must have created first).
        const now = Date.now();
        const rows = Array.from({ length: Number(q("n")) }, (_, i) =>
          env.DATA.prepare("INSERT INTO artifact_storage (scope, owner, key, value, updated_at) VALUES (?, ?, ?, 'v', ?)")
            .bind(q("scope") || "personal", q("owner"), `seed${String(i).padStart(4, "0")}`, now));
        if (rows.length > 0) await env.DATA.batch(rows);
        return Response.json({ seeded: rows.length });
      }
      case "/__count": {
        const row = await env.DATA.prepare("SELECT COUNT(*) AS n FROM artifact_storage WHERE scope = ? AND owner = ?")
          .bind(q("scope") || "personal", q("owner")).first<{ n: number }>();
        return Response.json({ n: row?.n ?? 0 });
      }
      case "/__race": {
        // Several storage calls run at once inside this one invocation, so
        // their D1 round trips interleave the way concurrent requests' can in
        // production. Over HTTP to one local isolate the first call tends to
        // finish before the next arrives, which hides a check-then-write race.
        const { subject, bodies } = (await request.json()) as { subject: string; bodies: unknown[] };
        const answers = await Promise.all(bodies.map((b) => call(storageRequest(subject, b), env)));
        return Response.json(await Promise.all(answers.map(async (r) => ({ status: r.status, body: await r.json() }))));
      }
      case "/__oversize": {
        // A body of `bytes` bytes, sent to the storage route inside this
        // invocation: once declaring its length, and once streamed in 100,000
        // byte chunks with no Content-Length. Over HTTP, wrangler dev's own
        // proxy can drop the connection when a Worker answers before reading
        // all of a body over about 4 MB, so the Worker's answer may not arrive.
        const bytes = Number(q("bytes"));
        const declared = await call(new Request("http://app.test/api/storage", {
          method: "POST",
          headers: { ...identity("alice"), "content-length": String(bytes) },
          body: "{}",
        }), env);
        const chunk = new Uint8Array(100_000).fill(0x78);
        const chunks = Math.ceil(bytes / chunk.byteLength);
        let pulled = 0;
        const stream = new ReadableStream<Uint8Array>({
          pull(c) {
            if (pulled++ < chunks) c.enqueue(chunk);
            else c.close();
          },
        });
        const streamedRequest = new Request("http://app.test/api/storage", { method: "POST", headers: identity("alice"), body: stream });
        const streamed = await call(streamedRequest, env);
        return Response.json({
          declared: await summary(declared),
          streamed: { ...(await summary(streamed)), contentLength: streamedRequest.headers.get("content-length"), pulled, chunks },
        });
      }
      default:
        return call(request, env);
    }
  },
};
