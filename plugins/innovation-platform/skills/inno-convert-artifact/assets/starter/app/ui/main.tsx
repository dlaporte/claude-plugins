// The interface's entry (the platform's CI builds app/ui/main.tsx). The
// storage shim comes first, so the artifact finds window.storage in place.
import "./storage-shim";
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import AppBar from "./AppBar";
import Artifact from "./Artifact";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <AppBar />
    <main id="main">
      <Artifact />
    </main>
  </StrictMode>,
);
