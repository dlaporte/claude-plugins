// window.storage as a Claude artifact sees it on claude.ai, backed by this
// app's own database through /api/storage. Each call keeps the artifact
// API's shape: an optional last argument `true` means shared storage (one
// copy for everyone who reaches the app), and leaving it out means personal
// storage (the signed-in person's own copy).
//
// Imported first by main.tsx, so the artifact's code finds window.storage
// already in place.

type Shared = boolean | undefined;

async function call(op: string, args: Record<string, unknown>): Promise<unknown> {
  const res = await fetch("/api/storage", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ op, ...args }),
  });
  if (!res.ok) {
    let reason = String(res.status);
    try {
      reason = ((await res.json()) as { error?: string }).error ?? reason;
    } catch {
      // keep the status
    }
    throw new Error(`storage ${op} failed: ${reason}`);
  }
  return res.json();
}

export interface StorageApi {
  get(key: string, shared?: boolean): Promise<{ key: string; value: string; shared: boolean } | null>;
  set(key: string, value: string, shared?: boolean): Promise<{ key: string; value: string; shared: boolean }>;
  delete(key: string, shared?: boolean): Promise<{ key: string; deleted: boolean; shared: boolean }>;
  list(prefix?: string, shared?: boolean): Promise<{ keys: string[]; prefix: string; shared: boolean }>;
}

export const storage: StorageApi = {
  get: (key: string, shared?: Shared) => call("get", { key, shared: shared === true }) as ReturnType<StorageApi["get"]>,
  set: (key: string, value: string, shared?: Shared) =>
    call("set", { key, value: String(value), shared: shared === true }) as ReturnType<StorageApi["set"]>,
  delete: (key: string, shared?: Shared) => call("delete", { key, shared: shared === true }) as ReturnType<StorageApi["delete"]>,
  list: (prefix?: string, shared?: Shared) =>
    call("list", { prefix: prefix ?? "", shared: shared === true }) as ReturnType<StorageApi["list"]>,
};

declare global {
  interface Window {
    storage: StorageApi;
  }
}

window.storage = storage;
