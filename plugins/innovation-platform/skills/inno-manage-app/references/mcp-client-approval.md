# When an MCP client cannot get into an app

Read this when a user's MCP client is refused while they authorize it,
keeps asking them to approve it again, meets a "Consent page expired" page,
or never reaches the approval page.

- **Refused at authorization.** A person the app does not admit is stopped
  when they authorize their MCP client, with a **No access** page that names
  the account they signed in with and the app, asks them to have it shared
  with that account, and offers to sign out to use another. The fix is the
  owner's `grant_access`, or widening the app to internal with
  `set_app_access` after the widening review (the skill's `set_app_access`
  section). The page's next step, after signing out, is to restart the
  app's connection in the MCP client and sign in with the account it is
  shared with (in Claude Code, `/mcp`, then Reconnect): an MCP client signs
  in again only when its connection restarts, so after the owner's
  `grant_access` the person restarts it the same way.
- **A public MCP app takes no authorization.** An anonymous app widened to
  public answers at its MCP address with no sign-in and no token, and the
  platform issues no token for it, so an authorization started for it is
  refused. The client connects without one.
- **Asked to approve again.** A new approval prompt is not a fault. From
  platform v0.18.27 the platform's own connection shows the consent page at
  every authorization, and an app's MCP client skips it only while its last
  grant for that app lives: the same client, redirect address, app and app
  instance, with its code exchanged. The grant a skipped page gives ends no
  later than that one, so the page comes back when it ends. A remembered
  approval is also forgotten whenever the person's grants are revoked or
  refused (`revoke_access`, a block, an admin's `revoke_sessions`, a re-add,
  a transfer that re-points the owner row, or a refused refresh or
  authorization), so their client asks again. A client whose redirect
  address changed asks again, and so does an app that was purged and later
  registered again under the same name, which is a new instance. Before
  v0.18.27 the platform remembered each person's approval of an MCP client,
  the platform's own connection included, per app instance and per client
  redirect address, for 90 days.
- **What the consent page says** (from platform v0.18.27). It names the
  client by its registered name, with its control, format (bidi and
  zero-width) and separator characters dropped and at most 80 characters, and says on a line of its own where the approval is
  sent ("If you approve, it is sent to <origin>.", with a note when that
  address is an app on this platform, which its owner runs, or has no
  host). Have the person read that line before approving: an approval sent
  to an address they do not recognize is one to deny. It states how long
  the approval lasts: an app's "This approval lasts up to N days and ends
  sooner if your access to the app is withdrawn; until then your MCP client
  may connect to the app again without this page.", the platform's "This
  approval lasts up to N days, and every new connection asks again."
- **"Consent page expired."** From platform v0.18.27 a consent page opened
  before the person's sessions were ended (an admin's `revoke_sessions`, a
  block, or their own sign-out, among others) answers "This consent page
  was opened before your sessions were ended. Start the connection again
  from your MCP client." It is not a fault: they restart the connection (in
  Claude Code, `/mcp`, then Reconnect) and sign in again. A page left open
  too long says "This consent page expired.", with the same remedy.
- **Asked to sign in again at the identity provider.** From platform
  v0.18.27 an MCP authorization asks for the same recent sign-in a browser
  sign-in does (the idle limit, or the session-age bound), so the identity
  provider may ask the person to sign in again even while a browser of
  theirs is signed in. That is expected: they sign in, and the
  authorization goes on.
- **Never reaches the approval page.** The client may be sending
  `response_type=code` with no `code_challenge`. The platform's OAuth server
  requires PKCE with `S256` on every authorization-code request,
  confidential clients included, and refuses a missing challenge, an
  unsupported method or `plain` with a 400. That is not a setting anyone
  can relax: it is the client's bug to fix.
