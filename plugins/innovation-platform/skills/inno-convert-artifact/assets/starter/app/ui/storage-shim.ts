// window.storage as a Claude artifact sees it on claude.ai, backed by this
// app's own database through /api/storage. Each call keeps the artifact
// API's shape: an optional last argument `true` means shared storage (one
// copy for everyone who reaches the app), and leaving it out means personal
// storage (the signed-in person's own copy).
//
// Imported first by main.tsx, so the artifact's code finds window.storage
// already in place.
//
// Every request the page makes goes through send(), which gives up after
// REQUEST_TIMEOUT_MS and never sends a request again by itself: a failed
// call rejects with a RequestError whose kind says what happened and whose
// message says it to a person (the page offers what to do next). A write
// whose answer was lost (no answer in time, a network failure, or a server
// error) may still have been stored, so its error has outcomeUnknown set:
// read before writing again. The platform answers 401 to a request once the
// person's session has ended, and send() then also tells the window
// (SIGNED_OUT), so the app bar can offer to sign in again whatever the
// artifact does with the error.

/** How long one request may take: room for the largest write (4 MB) on a slow connection. */
export const REQUEST_TIMEOUT_MS = 30_000;

/** The window event send() dispatches when a request is answered with 401. */
export const SIGNED_OUT = "app:signed-out";

/**
 * signed_out: the session has ended (401); loading the page signs in again.
 * refused: the app turned the request down (another 4xx) and changed nothing.
 * unavailable: the app could not answer just now (5xx, 408, 429).
 * timeout: no answer within REQUEST_TIMEOUT_MS.
 * network: no answer at all, or one cut off.
 */
export type Failure = "signed_out" | "refused" | "unavailable" | "timeout" | "network";

const SAYS: Record<Failure, string> = {
  signed_out: "Your session has ended: sign in again to continue",
  refused: "The app refused this request",
  unavailable: "The app could not answer just now",
  timeout: "The app took too long to answer",
  network: "The app could not be reached",
};

export class RequestError extends Error {
  readonly kind: Failure;
  /** The HTTP status, when an answer came. */
  readonly status: number | null;
  /** The app's own reason, such as too_many_keys, when it gave one. */
  readonly reason: string | null;
  /** True for a write whose answer was lost: it may have been stored. */
  readonly outcomeUnknown: boolean;

  constructor(kind: Failure, status: number | null = null, reason: string | null = null, outcomeUnknown = false) {
    // An answer the app gave names its reason (storage.ts's error), or its status.
    const why = kind === "refused" || kind === "unavailable" ? ` (${reason ?? status})` : "";
    const says = `${SAYS[kind]}${why}.`;
    super(outcomeUnknown ? `${says} It may have been saved: check before trying again.` : says);
    this.name = "RequestError";
    this.kind = kind;
    this.status = status;
    this.reason = reason;
    this.outcomeUnknown = outcomeUnknown;
  }
}

/**
 * Sends one request and reads its JSON answer, or rejects with a
 * RequestError. `write` marks a request that changes something, whose
 * outcome is unknown when its answer is lost.
 */
export async function send(path: string, init: RequestInit = {}, write = false): Promise<unknown> {
  const controller = new AbortController();
  const failed = (kind: Failure, status: number | null = null, reason: string | null = null) => {
    if (kind === "signed_out") window.dispatchEvent(new Event(SIGNED_OUT));
    // A 4xx answer means nothing was stored; without one, a write may have been.
    return new RequestError(kind, status, reason, write && (status === null || status >= 500));
  };
  let timer: ReturnType<typeof setTimeout> | undefined;
  const deadline = new Promise<never>((_, reject) => {
    timer = setTimeout(() => {
      controller.abort();
      reject(failed("timeout"));
    }, REQUEST_TIMEOUT_MS);
  });
  const attempt = async (): Promise<unknown> => {
    let res: Response;
    try {
      res = await fetch(path, { ...init, signal: controller.signal });
    } catch {
      throw failed("network");
    }
    if (res.status === 401) throw failed("signed_out", 401);
    if (!res.ok) {
      let reason: string | null = null;
      try {
        reason = ((await res.json()) as { error?: string }).error ?? null;
      } catch {
        // no reason given
      }
      const busy = res.status >= 500 || res.status === 408 || res.status === 429;
      throw failed(busy ? "unavailable" : "refused", res.status, reason);
    }
    try {
      return await res.json();
    } catch {
      throw failed("network");
    }
  };
  try {
    return await Promise.race([attempt(), deadline]);
  } finally {
    clearTimeout(timer);
  }
}

type Shared = boolean | undefined;

function call(op: string, args: Record<string, unknown>, write: boolean): Promise<unknown> {
  return send("/api/storage", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ op, ...args }) }, write);
}

export interface StorageApi {
  get(key: string, shared?: boolean): Promise<{ key: string; value: string; shared: boolean } | null>;
  set(key: string, value: string, shared?: boolean): Promise<{ key: string; value: string; shared: boolean }>;
  delete(key: string, shared?: boolean): Promise<{ key: string; deleted: boolean; shared: boolean }>;
  list(prefix?: string, shared?: boolean): Promise<{ keys: string[]; prefix: string; shared: boolean }>;
}

export const storage: StorageApi = {
  get: (key: string, shared?: Shared) => call("get", { key, shared: shared === true }, false) as ReturnType<StorageApi["get"]>,
  set: (key: string, value: string, shared?: Shared) =>
    call("set", { key, value: String(value), shared: shared === true }, true) as ReturnType<StorageApi["set"]>,
  delete: (key: string, shared?: Shared) => call("delete", { key, shared: shared === true }, true) as ReturnType<StorageApi["delete"]>,
  list: (prefix?: string, shared?: Shared) =>
    call("list", { prefix: prefix ?? "", shared: shared === true }, false) as ReturnType<StorageApi["list"]>,
};

declare global {
  interface Window {
    storage: StorageApi;
  }
}

window.storage = storage;
