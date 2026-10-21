# Connect page errors: what each one means

Used from `inno-add-connection` step 6 when a user reports an error page
after opening a connect link. The connect link opens a platform page, and
each failure it can show has one meaning. Read the page title the user
reports before changing anything. A pasted token or client pair the backend
rejects is not one of these: the form comes back with a sentence saying so,
and the fix is to copy it again.

**Not the person's own doing:**

- **"Not available"** ("That connection is not available to you"). One
  answer, on purpose, for several causes: the app name is wrong, the
  connection name is wrong, the connection is paused (`disabled`), or the
  person may not use the app. The page will not say which. Check in this
  order: `list_connections` for the app (does that connection name exist,
  and is it enabled), then whether the person may use the app. On a
  members-only app that means its member list (`grant_access` if they are
  not on it); an internal app admits everyone who signs in, so there the
  cause is one of the others. Never tell the user the backend is down.
- **"Connections unavailable"** (HTTP 503, "Connections is not enabled on
  this platform"). The platform's own Connections setup is missing. Nothing
  in the app or the connection fixes it: a platform admin does.
- **"Connection misconfigured"** (HTTP 503). The stored definition cannot be
  used: it no longer parses, its stored secret cannot be opened, or a
  pasted-token connection names a delivery header that cannot be sent. Read
  it with `list_connections`, and have the app's owner write it again with
  `set_app_connection` (step 4's approval rules apply); if it still fails, a
  platform admin looks at it.
- **"Connecting failed"** (HTTP 502 or 503, "Try again from your chat in a
  minute"). The backend's own sign-in or token address failed while the
  platform was checking or storing the credential, or the platform's
  sealing key was briefly unreachable. Wait a minute and start again from
  the chat; if it keeps failing, the backend is the place to look.

**The person's own account or browser:**

- **"Too many requests"** (HTTP 429, `Retry-After: 60`). The connect pages
  share a budget of 60 requests a minute per person with the platform
  panel's live reads. Wait a minute, then start again from the chat.
- **"Account inactive"** (HTTP 401). The person's Okta account is suspended
  or deprovisioned. Nothing about the connection can fix that.
- **"Your encryption key isn't reachable from here"**. The person's stored
  connections are sealed to them personally, and this browser session
  cannot unlock them. The page gives both ways out: use the app once from
  the chat (or the device where they last connected) and retry the link
  within the minutes it names, which loses nothing; or **Start fresh**,
  which removes every backend connection stored under their address, so
  they reconnect each one. Let them choose.

**The connect flow itself:**

- **"Finish in the browser you started in"** (`oauth2_code` only). The
  backend login was completed in a different browser, or a different browser
  profile, from the one that opened the connect link. Open the connect link
  again and finish the whole sign-in in that same browser.
- **"Connection declined"** (`oauth2_code` only). The person, or the
  backend, declined on the backend's own sign-in page. Start again from the
  chat if that was not meant.
- **"Link already used"** (`oauth2_code` only). The backend sent the person
  back with a link that was already used or has expired. Start again from
  the chat.
- **"Invalid connection link"** (`oauth2_code` only). The address the
  backend sent the person back to is malformed. Start again from the chat;
  if it repeats, check the connection's sign-in settings against the
  backend's documentation.
- **"This connection changed"**. The connection's strategy or a credential
  endpoint was changed while the person was connecting, so nothing was sent.
  Start again from the chat to see the current destination.
- **"Connection not stored"**. The person's stored credential changed while
  they were connecting (their access was revoked, or another connect attempt
  finished first), or, on their first connect, the connection's strategy or
  configuration was changed after the page checked it (a first credential is
  stored only under the definition it was fetched under). Nothing from this
  attempt was kept. Check with `list_user_connections` whether a credential
  is on file and whether the person still has access, and with
  `list_connections` that the definition is the one expected, then start
  again from the chat if it is not.

"Finish in the browser you started in", "This connection changed" and
"Connection not stored" are audited `connection_connect_refused` with the
reason (`browser_mismatch`, `endpoint_changed` or
`sink_changed_after_exchange`, `revoked_mid_exchange`), which a platform
admin can read with `query_audit`. A "Connection not stored" caused by a
definition change is audited `revoked_mid_exchange` too, so read it beside
the `connection_credentials_invalidated` and `connection_set` rows of the
same moment. A "Not available" for a person the app does not admit is
audited `connection_access_denied`.
