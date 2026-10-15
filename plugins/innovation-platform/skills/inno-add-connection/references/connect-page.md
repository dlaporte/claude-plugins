# Connect page errors: what each one means

Used from `inno-add-connection` step 6 when a user reports an error page
after opening a connect link. The connect link opens a platform page, and
each failure it can show has one meaning. Read the page title the user
reports before changing anything:

- **"Not available"** ("That connection is not available to you"). One
  answer, on purpose, for four different causes: the app name is wrong, the
  connection name is wrong, the connection is paused (`disabled`), or the
  person is not a member of the app. The page will not say which. Check in
  this order: `list_connections` for the app (does that connection name
  exist, and is it enabled), then whether the person has access to the app
  (`grant_access` if not). Never tell the user the backend is down. The page
  gives the same answer for a definition whose strategy the browser leg
  cannot start, but all three live strategies are startable there, so only
  a definition written by some future strategy could reach that case: the
  four causes above are still the ones to check.
- **"Too many requests"** (HTTP 429, `Retry-After: 60`). The connect pages
  share a budget of 60 requests a minute per person with the platform
  panel's live reads. Wait a minute, then start again from the chat.
- **"Account inactive"** (HTTP 401). The person's Okta account is suspended
  or deprovisioned. Nothing about the connection can fix that.
- **"Finish in the browser you started in"** (`oauth2_code` only). The
  backend login was completed in a different browser, or a different browser
  profile, from the one that opened the connect link. Open the connect link
  again and finish the whole sign-in in that same browser.
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

The last three are audited `connection_connect_refused` with the reason
(`browser_mismatch`, `endpoint_changed` or `sink_changed_after_exchange`,
`revoked_mid_exchange`), which a platform admin can read with `query_audit`.
A "Connection not stored" caused by a definition change is audited
`revoked_mid_exchange` too, so read it beside the
`connection_credentials_invalidated` and `connection_set` rows of the same
moment.
