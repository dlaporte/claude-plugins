// Placeholder for the artifact's own component: replace this file with the
// artifact's source, its default export unchanged. This stand-in exercises
// both kinds of storage, and shows what a page owes a person around each
// window.storage call (storage-shim.ts says how one fails): that a read is
// under way; that one failed, never shown as a count of zero; that a save is
// in flight, its button disabled until it ends, so clicks meanwhile send
// nothing; and, after a failure, a next step the person chooses: read again,
// sign in again, or, when a save's answer was lost, read the count before
// saving again. Nothing is sent again by itself. window.storage.set replaces
// a value; it is not an atomic increment, so two people adding to the shared
// count at the same moment can both save the same number.
import { useCallback, useEffect, useRef, useState } from "react";
import type { RequestError } from "./storage-shim";

type Count = { state: "loading" } | { state: "ready"; value: number } | { state: "failed"; error: RequestError };

function Counter({ label, shared }: { label: string; shared: boolean }) {
  const [count, setCount] = useState<Count>({ state: "loading" });
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState<RequestError | null>(null);
  // Set at once, where state waits for the next render, so a second click in
  // the same moment finds the save under way.
  const inFlight = useRef(false);

  const load = useCallback(async () => {
    setCount({ state: "loading" });
    setSaveError(null);
    try {
      const saved = await window.storage.get("count", shared);
      setCount({ state: "ready", value: saved ? Number(saved.value) : 0 });
    } catch (e) {
      setCount({ state: "failed", error: e as RequestError });
    }
  }, [shared]);

  useEffect(() => {
    void load();
  }, [load]);

  const add = async () => {
    if (count.state !== "ready" || inFlight.current) return;
    inFlight.current = true;
    setSaving(true);
    setSaveError(null);
    const next = count.value + 1;
    try {
      await window.storage.set("count", String(next), shared);
      setCount({ state: "ready", value: next });
    } catch (e) {
      setSaveError(e as RequestError);
    } finally {
      inFlight.current = false;
      setSaving(false);
    }
  };

  const error = count.state === "failed" ? count.error : saveError;
  const what = count.state === "failed" ? "Could not load the count." : error?.outcomeUnknown ? "The save did not finish." : "Not saved.";

  return (
    <div className="space-y-2">
      {count.state === "ready" && (
        <button type="button" className="rounded bg-blue-700 px-4 py-2 text-white disabled:opacity-60" disabled={saving} onClick={add}>
          {label}: {count.value}
        </button>
      )}
      <p role="status">{count.state === "loading" ? "Loading the count." : saving ? "Saving." : ""}</p>
      <div role="alert">
        {error && (
          <p>
            {what} {error.message}
          </p>
        )}
        {error?.kind === "signed_out" ? (
          <a href={window.location.href} className="underline">
            Sign in again
          </a>
        ) : count.state === "failed" ? (
          <button type="button" className="underline" onClick={load}>
            Try again
          </button>
        ) : error?.outcomeUnknown ? (
          <button type="button" className="underline" onClick={load}>
            Check the count
          </button>
        ) : null}
      </div>
    </div>
  );
}

export default function Artifact() {
  return (
    <section className="mx-auto max-w-md space-y-4 p-6">
      <h1 className="text-xl font-semibold">Counters</h1>
      <Counter label="Mine" shared={false} />
      <Counter label="Everyone" shared />
    </section>
  );
}
