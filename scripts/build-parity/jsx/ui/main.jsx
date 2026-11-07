// The JSX entry, with an imported stylesheet. styles.css imports Tailwind in
// its url() form, which both builders detect and hand to the Tailwind CLI;
// the CLI (4.3.3) leaves that form as it is, so no utility is expected.
import { createRoot } from "react-dom/client";
import "./card.css";

createRoot(document.getElementById("root")).render(
  <p className="card text-center" data-marker="parity-entry-jsx">Built from main.jsx.</p>,
);
