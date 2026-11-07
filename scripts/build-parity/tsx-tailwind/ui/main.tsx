// The TSX entry: JSX, Tailwind classes, an imported stylesheet (panel.css,
// which inlines a font) and an imported image. main.js beside it is never
// built: main.tsx comes first in the entry order.
import { createRoot } from "react-dom/client";
import logo from "./logo.png";
import "./panel.css";

function App({ title }: { title: string }) {
  return (
    <main className="flex items-center gap-4 p-6 text-center">
      <img src={logo} alt="" className="h-8 w-8" />
      <h1 className="panel-title text-2xl font-bold">{title}</h1>
      <p data-marker="parity-entry-tsx">Built from main.tsx.</p>
    </main>
  );
}

createRoot(document.getElementById("root")!).render(<App title="Parity" />);
