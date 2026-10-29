# When an MCP client cannot get into an app

Read this when a user's MCP client is refused while they authorize it,
keeps asking them to approve it again, or never reaches the approval page.

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
- **Asked to approve again.** The platform remembers each person's approval
  of an MCP client per app instance and per client redirect URI, so a new
  approval prompt is not a fault: a client whose redirect URI changed asks
  again, and an app that was purged and later registered again under the
  same name is a new instance that asks again.
- **Never reaches the approval page.** The client may be sending
  `response_type=code` with no `code_challenge`. The platform's OAuth server
  requires PKCE with `S256` on every authorization-code request,
  confidential clients included, and refuses a missing challenge, an
  unsupported method or `plain` with a 400. That is not a setting anyone
  can relax: it is the client's bug to fix.
