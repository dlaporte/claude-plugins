# When an MCP client cannot get into an app

Read this when a user's MCP client is refused while they authorize it,
keeps asking them to approve it again, or never reaches the approval page.

- **Refused at authorization.** A person the app does not admit is stopped
  when they authorize their MCP client, with "You don't have access to this
  app. Ask its owner to share it with you." The fix is the owner's
  `grant_access`, or opening the app with `set_app_access`.
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
