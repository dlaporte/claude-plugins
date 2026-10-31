// Placeholder for the artifact's own component: replace this file with the
// artifact's source, its default export unchanged. This stand-in exercises
// both kinds of storage, so the starter can be built and tried as it is.
import { useEffect, useState } from "react";

export default function Artifact() {
  const [mine, setMine] = useState(0);
  const [everyone, setEveryone] = useState(0);

  useEffect(() => {
    window.storage.get("count").then((r) => r && setMine(Number(r.value)));
    window.storage.get("count", true).then((r) => r && setEveryone(Number(r.value)));
  }, []);

  const bump = async (shared: boolean) => {
    const next = (shared ? everyone : mine) + 1;
    await window.storage.set("count", String(next), shared);
    (shared ? setEveryone : setMine)(next);
  };

  return (
    <section className="mx-auto max-w-md space-y-4 p-6">
      <h1 className="text-xl font-semibold">Counters</h1>
      <p>
        <button type="button" className="rounded bg-blue-700 px-4 py-2 text-white" onClick={() => bump(false)}>
          Mine: {mine}
        </button>
      </p>
      <p>
        <button type="button" className="rounded bg-blue-700 px-4 py-2 text-white" onClick={() => bump(true)}>
          Everyone: {everyone}
        </button>
      </p>
    </section>
  );
}
