// The server side of the artifact's window.storage (app/ui/storage-shim.ts).
// One D1 table holds every key: a personal key is scoped to the caller's
// identity provider ID (X-Forwarded-Subject), a shared key to no one, so
// everyone who reaches the app reads and writes the same copy, as a shared
// artifact's viewers do on claude.ai.
//
// Every operation is a POST from the app's own page: state never changes on
// a GET, and a request from any other page is refused (the app-security
// notes, CSRF). Every value is bound, never built into SQL, and keys, values
// and key counts are bounded.
import type { CurrentUserResult } from "./identity";

interface Env {
  DATA: D1Database;
}

export const MAX_KEY = 200;
export const MAX_VALUE = 1_000_000;
export const MAX_KEYS_PER_OWNER = 1_000;
export const MAX_LIST = 1_000;

const SCHEMA =
  "CREATE TABLE IF NOT EXISTS artifact_storage (" +
  "scope TEXT NOT NULL, owner TEXT NOT NULL, key TEXT NOT NULL, value TEXT NOT NULL, updated_at INTEGER NOT NULL, " +
  "PRIMARY KEY (scope, owner, key))";

let ready: Promise<unknown> | null = null;

function json(body: unknown, status: number, headers: Record<string, string>): Response {
  return Response.json(body, { status, headers: { ...headers, "Cache-Control": "private, no-store" } });
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

  let body: { op?: unknown; key?: unknown; value?: unknown; prefix?: unknown; shared?: unknown };
  try {
    body = await request.json();
  } catch {
    return json({ error: "bad_request" }, 400, headers);
  }
  const shared = body.shared === true;
  const scope = shared ? "shared" : "personal";
  const owner = shared ? "" : caller.subject;

  ready ??= env.DATA.prepare(SCHEMA).run();
  await ready;

  const keyOf = (k: unknown): string | null => (typeof k === "string" && k.length > 0 && k.length <= MAX_KEY ? k : null);

  switch (body.op) {
    case "get": {
      const key = keyOf(body.key);
      if (key === null) return json({ error: "bad_key" }, 400, headers);
      const row = await env.DATA.prepare("SELECT value FROM artifact_storage WHERE scope = ? AND owner = ? AND key = ?")
        .bind(scope, owner, key).first<{ value: string }>();
      return json(row ? { key, value: row.value, shared } : null, 200, headers);
    }
    case "set": {
      const key = keyOf(body.key);
      if (key === null) return json({ error: "bad_key" }, 400, headers);
      if (typeof body.value !== "string" || body.value.length > MAX_VALUE) return json({ error: "bad_value" }, 400, headers);
      const exists = await env.DATA.prepare("SELECT 1 FROM artifact_storage WHERE scope = ? AND owner = ? AND key = ?")
        .bind(scope, owner, key).first();
      if (!exists) {
        const count = await env.DATA.prepare("SELECT COUNT(*) AS n FROM artifact_storage WHERE scope = ? AND owner = ?")
          .bind(scope, owner).first<{ n: number }>();
        if ((count?.n ?? 0) >= MAX_KEYS_PER_OWNER) return json({ error: "too_many_keys" }, 400, headers);
      }
      await env.DATA.prepare(
        "INSERT INTO artifact_storage (scope, owner, key, value, updated_at) VALUES (?, ?, ?, ?, ?) " +
          "ON CONFLICT (scope, owner, key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at",
      ).bind(scope, owner, key, body.value, Date.now()).run();
      return json({ key, value: body.value, shared }, 200, headers);
    }
    case "delete": {
      const key = keyOf(body.key);
      if (key === null) return json({ error: "bad_key" }, 400, headers);
      const r = await env.DATA.prepare("DELETE FROM artifact_storage WHERE scope = ? AND owner = ? AND key = ?")
        .bind(scope, owner, key).run();
      return json({ key, deleted: (r.meta.changes ?? 0) > 0, shared }, 200, headers);
    }
    case "list": {
      const prefix = typeof body.prefix === "string" && body.prefix.length <= MAX_KEY ? body.prefix : "";
      const rows = await env.DATA.prepare(
        "SELECT key FROM artifact_storage WHERE scope = ? AND owner = ? AND substr(key, 1, ?) = ? ORDER BY key LIMIT ?",
      ).bind(scope, owner, prefix.length, prefix, MAX_LIST).all<{ key: string }>();
      return json({ keys: rows.results.map((r) => r.key), prefix, shared }, 200, headers);
    }
    default:
      return json({ error: "bad_op" }, 400, headers);
  }
}
