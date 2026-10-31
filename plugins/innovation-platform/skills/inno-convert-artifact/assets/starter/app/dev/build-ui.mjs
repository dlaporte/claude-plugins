// Local builds only: writes app/.ui-build/ui.ts the way the platform's CI
// does (the contract's "Browser interface"), with the esbuild and Tailwind
// CLI in this app's devDependencies, so `npm run dev` serves what a deploy
// would. CI never runs this file: it removes any app/.ui-build/ and builds
// its own with its own pinned tools.
//
// Usage (in app/): node dev/build-ui.mjs
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { build } from "esbuild";

const hash = (t) => createHash("sha256").update(t).digest("hex").slice(0, 16);
const assets = Object.fromEntries(
  [".png", ".jpg", ".jpeg", ".gif", ".webp", ".avif", ".svg", ".ico", ".woff", ".woff2", ".ttf", ".otf"].map((e) => [e, "dataurl"]),
);
const common = {
  bundle: true, platform: "browser", target: "es2022", minify: true, legalComments: "none",
  loader: assets, write: false, outdir: "/ui-out", define: { "process.env.NODE_ENV": '"production"' },
};

const entry = ["main.tsx", "main.ts", "main.jsx", "main.js"].map((e) => `ui/${e}`).find((p) => existsSync(p));
if (!entry) throw new Error("ui/ has no entry module (ui/main.tsx)");

let script = "";
let imported = "";
for (const f of (await build({ ...common, entryPoints: { ui: entry }, format: "esm", jsx: "automatic" })).outputFiles) {
  if (f.path.endsWith(".js")) script = f.text;
  else if (f.path.endsWith(".css")) imported = f.text;
}

let lead = "";
if (existsSync("ui/styles.css")) {
  const css = readFileSync("ui/styles.css", "utf8");
  if (/@import\s+(?:url\(\s*)?["']tailwindcss["']/.test(css)) {
    mkdirSync(".dev", { recursive: true });
    execFileSync("npx", ["--no-install", "tailwindcss", "--input", "styles.css", "--output", "../.dev/styles.css", "--minify"], { cwd: "ui", stdio: "inherit" });
    lead = readFileSync(".dev/styles.css", "utf8");
  } else {
    lead = (await build({ ...common, entryPoints: { styles: "ui/styles.css" } })).outputFiles.map((f) => f.text).join("");
  }
}

const styles = [lead, imported].filter(Boolean).join("\n");
rmSync(".ui-build", { recursive: true, force: true });
mkdirSync(".ui-build");
writeFileSync(".ui-build/ui.ts", [
  "// Generated locally by dev/build-ui.mjs. Do not commit it: CI builds its own.",
  `export const UI_SCRIPT_PATH = ${JSON.stringify(`/ui.${hash(script)}.js`)};`,
  `export const UI_STYLES_PATH = ${JSON.stringify(`/ui.${hash(styles)}.css`)};`,
  `export const UI_SCRIPT = ${JSON.stringify(script)};`,
  `export const UI_STYLES = ${JSON.stringify(styles)};`,
  "",
].join("\n"));
console.log(`built .ui-build/ui.ts: script ${script.length} bytes, styles ${styles.length} bytes`);
