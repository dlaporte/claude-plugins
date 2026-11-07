// Runs a Worker entry from the starter on workerd with a local D1, through
// the starter's own wrangler (unstable_dev, the stack `npm run dev` runs), and
// sends the requests the tests make. scripts/test-starter.sh copies this
// directory into a copy of the starter's app/ as app/suite/, so the paths here
// are relative to that app/.
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { unstable_dev } from "wrangler";
import { wranglerConfig } from "../dev/wrangler-config.mjs";

export const APP = resolve(fileURLToPath(new URL("..", import.meta.url)));

/**
 * Starts `entry` (a path under app/, such as "index.ts" or
 * "suite/fault-entry.ts") with the configuration dev/serve.mjs writes
 * (dev/wrangler-config.mjs), on a fresh local database. Each call is a new
 * isolate, so module state such as storage.ts's schema promise starts empty.
 */
export async function start(entry) {
  const dir = mkdtempSync(join(tmpdir(), "starter-test-"));
  const main = join(APP, entry);
  const config = join(dir, "wrangler.json");
  writeFileSync(config, JSON.stringify(wranglerConfig(main)));
  const worker = await unstable_dev(main, {
    config,
    local: true,
    persistTo: join(dir, "state"),
    logLevel: "error",
    experimental: { disableExperimentalWarning: true, testMode: true },
  });
  return {
    fetch: (path, init) => worker.fetch(path, init),
    stop: () => worker.stop(),
  };
}

/** The front door's identity headers for a signed-in person, on a same-origin request. */
export function person(subject) {
  return {
    "x-forwarded-user": `${subject}@example.edu`,
    "x-forwarded-subject": subject,
    "sec-fetch-site": "same-origin",
    "content-type": "application/json",
  };
}

/** Reads an answer as its status, its parsed JSON body (undefined when it is not JSON) and its headers. */
export async function answer(response) {
  const text = await response.text();
  let body;
  try {
    body = JSON.parse(text);
  } catch {
    body = undefined;
  }
  return { status: response.status, body, text, headers: response.headers };
}

/**
 * POSTs one storage call as `subject`. `body` is sent as JSON unless `raw`,
 * when it is sent as it is (a string or a stream).
 */
export async function storage(worker, body, { subject = "alice", raw = false, headers = {}, ...init } = {}) {
  return answer(await worker.fetch("/api/storage", {
    method: "POST",
    headers: { ...person(subject), ...headers },
    body: raw ? body : JSON.stringify(body),
    ...init,
  }));
}

/** GETs one of fault-entry.ts's test routes and parses its JSON answer. */
export async function control(worker, path) {
  const r = await worker.fetch(path);
  if (!r.ok) throw new Error(`${path} answered ${r.status}: ${await r.text()}`);
  return r.json();
}
