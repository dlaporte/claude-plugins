# What an artifact gets on claude.ai, and what it becomes here

An artifact runs in a sandboxed frame on claude.ai, which provides a few
things the artifact's code never declares. Each one needs a home in the app.

| On claude.ai | In the converted app |
|---|---|
| React compiled in the browser, libraries provided | `app/ui/`, built by the platform's CI (contract section 1.1, Browser interface); each library a pinned entry under `dependencies` in `app/package.json` (`libraries.md`) |
| Tailwind utility classes, always available | `app/ui/styles.css` holding `@import "tailwindcss";`, built by CI's pinned Tailwind CLI over `app/ui/` |
| `window.storage`, personal | `app/ui/storage-shim.ts` and `app/storage.ts`: one D1 table, each key scoped to the signed-in person's `X-Forwarded-Subject` |
| `window.storage`, shared (`true` as the last argument) | the same table with no owner: one copy for everyone who reaches the app |
| `window.claude.complete(prompt)` | not supported in this version: removed, and listed in the plan |
| A share link anyone with the link can open | the platform's front door: members-only at first, widened through `inno-manage-app` |
| No response headers | the starter's Content-Security-Policy, `nosniff`, `Referrer-Policy`, and `private, no-store` on the page and the API |
| `localStorage`, `sessionStorage` | unchanged: they work, per browser |

## window.storage

The shim keeps the shape artifacts use. Anthropic's public documentation
does not list these methods; the shape below is the one in common use and
observed behavior, so test any edge an artifact relies on.

```js
await window.storage.set(key, value, shared?)   // { key, value, shared }
await window.storage.get(key, shared?)          // { key, value, shared }, or null when the key is not there
await window.storage.delete(key, shared?)       // { key, deleted, shared }
await window.storage.list(prefix?, shared?)     // { keys, prefix, shared }
```

- `shared` is `true` for shared storage; anything else means personal.
- Values are strings, as on claude.ai: artifacts store JSON with
  `JSON.stringify` and read it back with `JSON.parse`. The shim turns a
  non-string into a string with `String(value)`.
- Unverified edges: on claude.ai a `get` of a missing key may throw rather
  than return `null`. The shim returns `null`; an artifact that catches the
  throw still works, one that tests for `null` works too.
- Limits (in `app/storage.ts`): keys up to 200 characters, values up to
  1,000,000 characters, 1,000 keys per person (and 1,000 shared), `list`
  returns at most 1,000 keys. A call over a limit throws, with the reason in
  the error's message. Raise a limit only with a reason: they bound what one
  person can store.
- Every call needs a signed-in person, shared ones included, since the app
  is identity-aware. Data saved on claude.ai does not move over.

## Shared data is visible to everyone who reaches the app

On claude.ai, shared storage is visible to everyone the artifact is shared
with. Here it is visible to everyone who reaches the app: its members at
first, everyone who signs in once it is widened to internal. Say so in the
plan when the artifact writes anything personal to shared storage.

## What the page may load

The starter's policy is `default-src 'self'` with `script-src 'self'`,
`style-src 'self'`, `img-src 'self' data:`, `font-src 'self' data:` and
`connect-src 'self'`. So:

- every script comes from the built bundle (no CDN `<script>` tags);
- images and fonts come from the bundle (CI inlines imported ones as data
  URLs) or from the app itself;
- `fetch` reaches only the app's own routes;
- a library that injects a `<style>` element at run time is blocked; style
  attributes set by React work.
