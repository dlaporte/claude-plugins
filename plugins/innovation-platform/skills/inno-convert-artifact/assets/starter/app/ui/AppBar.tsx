// Who is signed in, and the sign-out link (the contract's R4): /_auth/signout
// belongs to the platform on every app host. The address comes from /api/me,
// after the words "Signed in as", which only a screen reader reads. A read
// that fails is said in the bar, with Try again, and the sign-out link stays.
// Once the session has ended (a 401 here, or from any storage call:
// storage-shim.ts's SIGNED_OUT) the bar offers to sign in again by loading
// the page, which the platform sends through its sign-in. A caller with no
// address, such as a public app's visitor, sees neither.
import { useCallback, useEffect, useState } from "react";
import { RequestError, SIGNED_OUT, send } from "./storage-shim";

type Me =
  | { state: "checking" }
  | { state: "known"; email: string | null }
  | { state: "failed"; error: RequestError };

/** The next state, unless the session has ended: only loading the page changes that. */
const unlessEnded = (next: Me) => (was: Me): Me => (was.state === "failed" && was.error.kind === "signed_out" ? was : next);

export default function AppBar() {
  const [me, setMe] = useState<Me>({ state: "checking" });

  const check = useCallback(async () => {
    setMe({ state: "checking" });
    try {
      const { email } = (await send("/api/me")) as { email: string | null };
      setMe(unlessEnded({ state: "known", email }));
    } catch (e) {
      setMe(unlessEnded({ state: "failed", error: e as RequestError }));
    }
  }, []);

  useEffect(() => {
    void check();
    const ended = () => setMe({ state: "failed", error: new RequestError("signed_out", 401) });
    window.addEventListener(SIGNED_OUT, ended);
    return () => window.removeEventListener(SIGNED_OUT, ended);
  }, [check]);

  const ended = me.state === "failed" && me.error.kind === "signed_out";
  const signedIn = (me.state === "known" && me.email !== null) || (me.state === "failed" && !ended);

  return (
    <header className="flex items-center justify-between gap-4 border-b border-gray-200 px-4 py-2 text-sm">
      <a href="#main" className="sr-only focus:not-sr-only">
        Skip to content
      </a>
      <span className="font-medium">APP_TITLE</span>
      <span className="flex items-center gap-3">
        {me.state === "known" && me.email && (
          <span>
            <span className="sr-only">Signed in as </span>
            {me.email}
          </span>
        )}
        <span role="status">
          {me.state === "failed" && (ended ? me.error.message : `Could not check who is signed in. ${me.error.message}`)}
        </span>
        {me.state === "failed" && !ended && (
          <button type="button" className="underline" onClick={check}>
            Try again
          </button>
        )}
        {ended && (
          <a href={window.location.href} className="underline">
            Sign in again
          </a>
        )}
        {signedIn && (
          <a href="/_auth/signout" className="underline">
            Sign out
          </a>
        )}
      </span>
    </header>
  );
}
