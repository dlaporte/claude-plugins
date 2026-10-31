# HTML artifacts

An HTML artifact is a whole page: markup, a `<style>` block, `<script>`
blocks, often a CDN `<script>` tag or two (the Tailwind CDN is common), and
inline handlers such as `onclick="..."`. It goes through `app/ui/` like a
React artifact, so the page keeps the strict policy and every library is
audited. The markup and the CSS carry over unchanged; the scripts move.

1. **Entry.** Use `app/ui/main.ts` instead of `main.tsx`, and delete the
   starter's `main.tsx`, `AppBar.tsx` and `Artifact.tsx`. Keep
   `storage-shim.ts`, imported first:

   ```ts
   import "./storage-shim";
   import "./artifact.css";
   import { mountAppBar } from "./app-bar";
   import { body } from "./artifact-markup";
   ```

2. **Markup.** Move the artifact's `<body>` content into
   `app/ui/artifact-markup.ts` as one exported constant string, and set it
   with `document.getElementById("root")!.innerHTML = body;` in `main.ts`.
   That string is the artifact's own fixed markup, never anything a person
   typed: data a person enters is shown with `textContent`, never written
   into HTML (`get_app_security` section 3). If the semgrep gate flags the
   assignment, build the markup with `document.createElement` instead.
3. **Styles.** Move the `<style>` block to `app/ui/artifact.css`. If the
   page used the Tailwind CDN, keep `app/ui/styles.css` (`@import
   "tailwindcss";`): CI scans `app/ui/` for the class names, including the
   markup string.
4. **Scripts.** Move each inline `<script>` block into `main.ts` (or modules
   it imports), after the markup is set. Replace each CDN `<script>` with
   its npm package (`libraries.md`) and an `import`.
5. **Inline handlers.** The policy blocks `onclick="..."` and every other
   `on...=` attribute. Give each element an `id` (or a `data-` attribute) and
   attach the handler in `main.ts`:

   ```ts
   document.getElementById("add")!.addEventListener("click", addItem);
   ```

   A function the handlers called from the global scope becomes a module
   function; nothing needs to be on `window` except `window.storage`.
6. **Who is signed in, and sign-out.** Replace the React `AppBar` with
   `app/ui/app-bar.ts`: a `<header>` element showing the address from
   `GET /api/me` (set with `textContent`) and a link to `/_auth/signout`,
   shown only when there is an address.
7. **Title.** The page's `<title>` is the one in `app/index.ts`
   (`APP_TITLE`); the artifact's own `<title>` goes there.

Then continue with step 6's dependencies and `CLAUDE.md` items.
