// The server side of the artifact's window.storage (app/ui/storage-shim.ts).
// One D1 table holds every key: a personal key is scoped to the caller's
// identity provider ID (X-Forwarded-Subject), a shared key to no one, so
// everyone who reaches the app reads and writes the same copy, as a shared
// artifact's viewers do on claude.ai.
//
// Every operation is a POST from the app's own page: state never changes on
// a GET, and a request from any other page is refused (the app-security
// notes, CSRF). Every value is bound, never built into SQL, and the body,
// keys, values and key counts are bounded. A call is checked whole before any
// statement runs, so a refused one touches nothing, and a database fault
// answers 503 storage_unavailable, never an unhandled exception.
import type { CurrentUserResult } from "./identity";

/** The Worker's bindings, named once here: index.ts imports this. */
export interface Env {
  DATA: D1Database;
}

export const MAX_KEY = 200;
// In bytes of UTF-8, as D1 counts: production D1 refuses a string or a row
// over 2,000,000 bytes, and this leaves room for the row's other columns.
export const MAX_VALUE_BYTES = 1_900_000;
// Twice a value's limit, since JSON writes a quote or backslash as two bytes, plus room for the rest.
export const MAX_BODY_BYTES = 2 * MAX_VALUE_BYTES + 200_000;
export const MAX_KEYS_PER_OWNER = 1_000;
export const MAX_LIST = 1_000;

const SCHEMA =
  "CREATE TABLE IF NOT EXISTS artifact_storage (" +
  "scope TEXT NOT NULL, owner TEXT NOT NULL, key TEXT NOT NULL, value TEXT NOT NULL, updated_at INTEGER NOT NULL, " +
  "PRIMARY KEY (scope, owner, key))";

let ready: Promise<unknown> | null = null;
const utf8 = new TextEncoder();

/**
 * Creates the table on this isolate's first storage call. Calls that arrive
 * together share one attempt, and a failed attempt is forgotten, so the next
 * call tries again: an isolate serves many requests, and a cached failure
 * would fail every one of them until the isolate went away.
 */
function schemaReady(db: D1Database): Promise<unknown> {
  ready ??= db.prepare(SCHEMA).run().catch((e: unknown) => {
    ready = null;
    throw e;
  });
  return ready;
}

function json(body: unknown, status: number, headers: Record<string, string>): Response {
  return Response.json(body, { status, headers: { ...headers, "Cache-Control": "private, no-store" } });
}

/**
 * The request's body as text, or null when it is over MAX_BODY_BYTES. A
 * declared Content-Length is checked first, but a streamed body declares
 * none, so the bytes are counted as they arrive too, and reading stops at the
 * limit. Throws when the body cannot be read.
 */
async function readBody(request: Request): Promise<string | null> {
  const declared = Number(request.headers.get("content-length"));
  if (Number.isFinite(declared) && declared > MAX_BODY_BYTES) {
    await request.body?.cancel().catch(() => {});
    return null;
  }
  if (!request.body) return "";
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > MAX_BODY_BYTES) {
      await reader.cancel().catch(() => {});
      return null;
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(total);
  let at = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, at);
    at += chunk.byteLength;
  }
  return new TextDecoder().decode(bytes);
}

/** One storage call, as its body asked for it and checked whole. */
type Call =
  | { op: "get" | "delete"; key: string }
  | { op: "set"; key: string; value: string }
  | { op: "list"; prefix: string };

/** The call a request's body asks for, or the reason it is refused. */
function parseCall(body: Record<string, unknown>): Call | { error: string } {
  const key = typeof body.key === "string" && body.key.length > 0 && body.key.length <= MAX_KEY ? body.key : null;
  switch (body.op) {
    case "get":
    case "delete":
      return key === null ? { error: "bad_key" } : { op: body.op, key };
    case "set":
      if (key === null) return { error: "bad_key" };
      if (typeof body.value !== "string" || utf8.encode(body.value).byteLength > MAX_VALUE_BYTES) {
        return { error: "bad_value" };
      }
      return { op: "set", key, value: body.value };
    case "list": {
      // The shim always sends a prefix; a missing one lists every key.
      const prefix = body.prefix === undefined ? "" : body.prefix;
      if (typeof prefix !== "string" || prefix.length > MAX_KEY) return { error: "bad_prefix" };
      return { op: "list", prefix };
    }
    default:
      return { error: "bad_op" };
  }
}

/** True when the request came from this app's own page. */
export function sameOrigin(request: Request): boolean {
  const site = request.headers.get("sec-fetch-site");
  if (site !== null) return site === "same-origin";
  const origin = request.headers.get("origin");
  const host = request.headers.get("x-forwarded-host");
  return origin !== null && host !== null && origin === `https://${host}`;
}

export async function handleStorage(
  request: Request,
  env: Env,
  caller: CurrentUserResult | null,
  headers: Record<string, string>,
): Promise<Response> {
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405, headers);
  if (!sameOrigin(request)) return json({ error: "cross_origin" }, 403, headers);
  if (!caller || !caller.subject) return json({ error: "no_signed_in_user" }, 403, headers);

  let body: unknown;
  try {
    const text = await readBody(request);
    if (text === null) return json({ error: "body_too_large" }, 413, headers);
    body = JSON.parse(text);
  } catch {
    return json({ error: "bad_request" }, 400, headers);
  }
  if (typeof body !== "object" || body === null || Array.isArray(body)) return json({ error: "bad_request" }, 400, headers);
  const fields = body as Record<string, unknown>;
  const call = parseCall(fields);
  if ("error" in call) return json({ error: call.error }, 400, headers);
  const shared = fields.shared === true;
  const scope = shared ? "shared" : "personal";
  const owner = shared ? "" : caller.subject;

  try {
    await schemaReady(env.DATA);
    switch (call.op) {
      case "get": {
        const row = await env.DATA.prepare("SELECT value FROM artifact_storage WHERE scope = ? AND owner = ? AND key = ?")
          .bind(scope, owner, call.key).first<{ value: string }>();
        return json(row ? { key: call.key, value: row.value, shared } : null, 200, headers);
      }
      case "set": {
        // One statement, with the quota checked inside it: a key that exists
        // is overwritten, and a new one is written only while the owner holds
        // fewer than MAX_KEYS_PER_OWNER. Checked in a separate statement
        // first, concurrent writes could all pass the check and overshoot
        // it, and keys past MAX_LIST would drop out of list().
        const r = await env.DATA.prepare(
          "INSERT INTO artifact_storage (scope, owner, key, value, updated_at) SELECT ?1, ?2, ?3, ?4, ?5 " +
            "WHERE EXISTS (SELECT 1 FROM artifact_storage WHERE scope = ?1 AND owner = ?2 AND key = ?3) " +
            "OR (SELECT COUNT(*) FROM artifact_storage WHERE scope = ?1 AND owner = ?2) < ?6 " +
            "ON CONFLICT (scope, owner, key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at",
        ).bind(scope, owner, call.key, call.value, Date.now(), MAX_KEYS_PER_OWNER).run();
        if ((r.meta.changes ?? 0) === 0) return json({ error: "too_many_keys" }, 400, headers);
        return json({ key: call.key, value: call.value, shared }, 200, headers);
      }
      case "delete": {
        const r = await env.DATA.prepare("DELETE FROM artifact_storage WHERE scope = ? AND owner = ? AND key = ?")
          .bind(scope, owner, call.key).run();
        return json({ key: call.key, deleted: (r.meta.changes ?? 0) > 0, shared }, 200, headers);
      }
      case "list": {
        // The prefix's length is SQLite's own count of its characters:
        // JavaScript's counts UTF-16 units, two for an emoji. substr, not
        // LIKE, so % and _ in a prefix match only themselves.
        const rows = await env.DATA.prepare(
          "SELECT key FROM artifact_storage WHERE scope = ?1 AND owner = ?2 AND substr(key, 1, length(?3)) = ?3 " +
            "ORDER BY key LIMIT ?4",
        ).bind(scope, owner, call.prefix, MAX_LIST).all<{ key: string }>();
        return json({ keys: rows.results.map((r) => r.key), prefix: call.prefix, shared }, 200, headers);
      }
    }
  } catch (e) {
    console.error("storage: the database call failed:", e);
    return json({ error: "storage_unavailable" }, 503, headers);
  }
}
