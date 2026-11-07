# HTML artifacts

An HTML artifact is a whole page: markup, a `<style>` block, `<script>`
blocks, often a CDN `<script>` tag or two (the Tailwind CDN is common), and
inline handlers such as `onclick="..."`, and inline styles such as
`style="..."`. It goes through `app/ui/` like a React artifact, so the page
keeps the strict policy and every library is audited. The markup carries
over except its `style` attributes, which become classes; the CSS carries
over unchanged, and the scripts move.

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
   into HTML (`get_app_security` §3). If the semgrep gate flags the
   assignment, build the markup with `document.createElement` instead. Its
   `style` attributes come out first (step 6 below).
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
6. **Inline styles.** The policy (`style-src 'self'`) also blocks every
   literal `style="..."` attribute, in HTML and in SVG alike, and one a
   script writes, in an HTML string or with `setAttribute("style", ...)`. The
   browser drops the style without a word on the page and logs a
   Content-Security-Policy error, so the artifact looks wrong rather than
   broken. Move each into a class in `app/ui/artifact.css` and give the
   element that class instead:

   ```html
   <div class="card" style="padding: 20px; color: #b00">
   <!-- becomes -->
   <div class="card card-warning">
   ```

   ```css
   .card-warning { padding: 20px; color: #b00; }
   ```

   Add the new classes at the end of `app/ui/artifact.css`. A `style`
   attribute outranked every rule in the stylesheet, and a class does not:
   where an existing rule with a more specific selector (`.list .card`, say)
   sets the same property, give the new rule a selector at least as specific
   (`.list .card-warning`), or the old rule wins and the element looks
   different.

   A style a script sets goes through the element's `style` property, which
   the policy allows: `el.setAttribute("style", s)` becomes
   `el.style.cssText = s`, and a value worked out at run time is set as
   `el.style.width = pct + "%"`. SVG presentation attributes such as
   `fill="..."` are not `style` and stay. Never add `'unsafe-inline'` to the
   policy to keep the attributes.
7. **Who is signed in, and sign-out.** Replace the React `AppBar` with
   `app/ui/app-bar.ts`, doing what `AppBar.tsx` does: a `<header>` element
   that reads `GET /api/me` through `send()` from `storage-shim.ts`, and
   shows the address (set with `textContent`) after the words `Signed in as `
   in an element with the `sr-only` class, beside a link to
   `/_auth/signout`. When the read fails, it says so in a `role="status"`
   element, with a Try again button, and keeps the sign-out link; once the
   session has ended (a `RequestError` of kind `signed_out`, or the shim's
   `SIGNED_OUT` event on `window`), it says so with a Sign in again link to
   the page itself instead, at the address the shim's `signInAddress()`
   builds (pathname plus search, never the fragment: a link that keeps a
   `#main` fragment only scrolls). A caller with no address sees neither
   link.
8. **Title.** The page's `<title>` is the one in `app/index.ts`
   (`APP_TITLE`); the artifact's own `<title>` goes there.

Then continue with SKILL.md step 6's dependencies and `CLAUDE.md` items.
