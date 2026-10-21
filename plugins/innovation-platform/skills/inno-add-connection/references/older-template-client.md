# An older template client: what it lacks and how to replace it

Used from `inno-add-connection` step 5 when the repo's `app/storage.py` (or
`lib/storage.js`) has no `ConnectionLocked` or no `ConnectionsError`. The
template's clients are each repo's own copies, so a repo created from an
older copy of the template keeps the client it was created with.

What an older client cannot do:

- **No `ConnectionLocked`**: it raises plain `NotConnected` for a locked
  credential too, so the app cannot tell "connected, but locked for this MCP
  client" from "never connected", and the locked case goes down the
  connect-link path, where the user loops.
- **No `ConnectionsError`**: its JS client throws a plain `Error` with no
  `.code`, so a paused backend falls through to the rethrow as a hard
  failure, and its Python client raises a plain `httpx.HTTPStatusError`, on
  which `e.code` raises `AttributeError`.

The fix: copy the current `app/storage.py` (or, in a JS container,
`lib/storage.js`) from the template repo (the `Template repo:` line of the
status you read in the Version gate) before writing the branches in step 5.
The current client brings `ConnectionLocked`, `ConnectionsError` and the
`truncated` flag on the file listing, and keeps the old shapes but one:

- the file listing is still a list;
- `NotConnected` is unchanged, and the JS one keeps its older field name
  `connectUrl` beside `connect_url`;
- the Python `ConnectionsError` is still an `httpx.HTTPStatusError`, so an
  existing `except httpx.HTTPStatusError` still catches it;
- the JS message is still `connections_error:<status>`.

The one changed shape is the identity helper (`current_user` in Python,
`currentUser` in JS). The current one answers no user (`None`, `null`) for
a caller with no identity, where an older one answered an empty email, and
its answer adds `member` and `subject`, the key for per-person data. After
the copy, make every place that reads the helper handle no user first and
never default it into a value (`inno-platform-conventions`' **Identity**
section).

The text of a failed seam call's error, as a whole, changed as well in
both clients: in Python `str(e)` is now `connections_error:<status>` rather
than httpx's own text, and in JS `String(e)` names `ConnectionsError` where
it used to name `Error`. That matters only to code that logs or matches that
text; check the app for such code after the copy.
