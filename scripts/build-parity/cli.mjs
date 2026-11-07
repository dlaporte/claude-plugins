// Stands in for the platform's ci/cli.mjs beside the platform's
// ci/build-ui.mjs, which imports these four names from it, when
// scripts/test-build-parity.sh runs that builder: only the builder itself is
// fetched and checked against the pinned record's sha256, so nothing else
// from the platform runs here. Its annotations print as plain lines.
import { realpathSync } from "node:fs";
import { pathToFileURL } from "node:url";

// True when node was started on the module itself, as CI runs the builder;
// false when another script imports it.
export function isMainModule(url) {
  try {
    return pathToFileURL(realpathSync(process.argv[1])).href === url;
  } catch {
    return false;
  }
}
export const logSafe = (s, n = 200) => String(s).slice(0, n);
export function annotate({ level = "error", title, what, fix = "", file }) {
  console.error(`${level}: ${title}: ${what}${file ? ` (${file})` : ""}${fix ? `; ${fix}` : ""}`);
}
export function annotateAll({ level = "error", title, fix = "", items }) {
  for (const item of items) annotate({ level, title, fix, ...item });
}
