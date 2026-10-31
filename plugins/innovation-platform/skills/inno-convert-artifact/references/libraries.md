# Libraries an artifact imports

claude.ai gives a React artifact a set of libraries without any manifest.
Each one the artifact imports becomes an exact pin under `dependencies` in
`app/package.json`: the platform's CI installs the interface's packages with
the Worker's and audits them the same way. Look up the current version with
`npm view <package> version` and prefer one that has been out a few weeks
(a platform cooldown refuses a version that is too new).

| Import in the artifact | npm package | Notes |
|---|---|---|
| `react`, `react-dom` | `react`, `react-dom` | already in the starter |
| `lucide-react` | `lucide-react` | icons; tree-shaken by the build |
| `recharts` | `recharts` | charts; sets style attributes, which the policy allows |
| `lodash` | `lodash` | or `lodash-es`, which bundles smaller |
| `d3` | `d3` | |
| `papaparse` | `papaparse` | CSV parsing |
| `mathjs` | `mathjs` | |
| `three` | `three` | 3D; a `canvas` or WebGL page needs nothing more |
| `chart.js` | `chart.js` | |
| `tone` | `tone` | audio |
| `xlsx` (SheetJS) | see the note | SheetJS publishes current versions from its own CDN, not npm; prefer `exceljs` or ask the user |
| `@/components/ui/<name>` (shadcn/ui) | none: source files | copy each component's source into `app/ui/components/ui/<name>.tsx` from the shadcn/ui registry, with the packages it imports (`@radix-ui/react-*`, `class-variance-authority`, `clsx`, `tailwind-merge`); rewrite the `@/` import paths as relative ones |

Anything else the artifact imports: find its npm package, pin it, and say
so in the plan.

## Fixes the page's policy can call for

- **A CDN `<script>` or `<link>`** (common in HTML artifacts): replace it
  with the npm package, imported from `app/ui/main.ts`.
- **A web font from a font CDN**: install the font's npm package (for
  example `@fontsource/<font>`) and import its CSS from `app/ui/main.tsx`;
  CI inlines the font files.
- **A library that injects `<style>` at run time** (some CSS-in-JS):
  prefer its static-CSS mode, or Tailwind classes; the policy blocks
  injected styles.
- **`eval` or `new Function`** in the artifact or a library: blocked by
  `script-src 'self'`. Rewrite the artifact's own use; replace a library
  that needs it.
