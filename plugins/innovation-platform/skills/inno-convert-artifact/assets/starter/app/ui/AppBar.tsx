// Who is signed in, and the sign-out link (the contract's R4): /_auth/signout
// belongs to the platform on every app host. Shown only when there is a
// signed-in person.
import { useEffect, useState } from "react";

export default function AppBar() {
  const [email, setEmail] = useState<string | null>(null);

  useEffect(() => {
    fetch("/api/me")
      .then((r) => (r.ok ? (r.json() as Promise<{ email: string | null }>) : { email: null }))
      .then((me) => setEmail(me.email))
      .catch(() => setEmail(null));
  }, []);

  return (
    <header className="flex items-center justify-between gap-4 border-b border-gray-200 px-4 py-2 text-sm">
      <a href="#main" className="sr-only focus:not-sr-only">
        Skip to content
      </a>
      <span className="font-medium">APP_TITLE</span>
      {email && (
        <span className="flex items-center gap-3">
          <span>{email}</span>
          <a href="/_auth/signout" className="underline">
            Sign out
          </a>
        </span>
      )}
    </header>
  );
}
