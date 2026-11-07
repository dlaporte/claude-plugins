// The Worker's local configuration, kept here alone: dev/serve.mjs writes it
// to .dev/wrangler.jsonc for `npm run dev`, and the plugin's test suite for
// this starter runs the Worker with it too, so both run the Worker alike.
// Importing this file only defines the function: it writes nothing.
//
// A deploy uses none of it. The platform bundles app/index.ts with its own
// configuration and binds the app's database itself; the compatibility date
// and flags below are kept to the platform's own, so a local run behaves as a
// deployed one does.
//
// `main` is the Worker's entry, relative to the directory the configuration
// is written to (or absolute).
export function wranglerConfig(main) {
  return {
    name: "local-app",
    main,
    compatibility_date: "2026-10-13",
    compatibility_flags: ["nodejs_compat"],
    d1_databases: [{ binding: "DATA", database_name: "local", database_id: "local" }],
  };
}
