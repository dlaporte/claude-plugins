# When an account is deactivated

Read this when a person meets the "Sign-in refused" page or a platform tool
answers `account_inactive`, or when someone asks why an app's owner changed
to a platform admin.

The platform runs in one of two membership modes, which the
`Identity provider:` line of the status you read in the Version gate names.
In `membership jit` anyone the identity provider lets sign in is a member,
and the platform never learns that an account was deactivated there: that
person keeps what they had until their sessions and grants end, and only a
platform admin can end it sooner (a delete the identity provider pushes over
SCIM still ends their way in through an app's identity provider group,
described in the skill's `grant_access` section). In `membership scim` the
identity provider also tells the platform who belongs, and a deactivation
reaches the platform as soon as the identity provider pushes it (some
providers push as changes happen, others on a schedule):

- If a download link, a Connections page, the panel's sign-in or the MCP
  client's sign-in to the platform (re-authorizing the connector) shows the
  "Sign-in refused" page (HTTP 403, "This account can no longer sign in."),
  or a panel request or a platform tool answers `account_inactive` (HTTP
  401), the identity provider deactivated or deleted that person's account, or never
  told the platform about it. The platform has ended their sessions and
  nothing in this skill can undo it: the account has to be reactivated, or
  provisioned, at the identity provider, by the identity team or a platform
  admin. The same account check ends their access to every app, MCP and
  browser alike, and their platform tool calls, as follows. In scim mode a
  deactivation ends their panel and browser app sessions at once; their MCP
  tokens and platform tool calls stop within the window
  `auth.status_check_minutes` sets (default 1 minute; a
  platform-scope setting, which only an admin's `get_config` catalog lists),
  plus the front door's introspection cache (contract R3); and a browser
  app's front door holds an answer for at most 10 seconds. From platform
  v0.18.27 the deactivation also revokes every MCP grant they hold, the
  platform's and each app's, and forgets the approvals their MCP clients
  remembered, so once the account is reactivated they sign in again and
  reconnect each MCP client. An admin whose
  account is deactivated loses admin standing. A person merely suspended
  keeps their stored connection credentials, and a deleted account loses
  them.
- **The apps that person owns move into a platform admin's custody** as
  soon as that push arrives: the admin becomes their owner (`app_status` names them), and each
  app keeps running, with its audience, its member list, its data links and
  its data, so the people it was shared with keep their access. Meanwhile
  only a platform admin can manage it. From platform v0.18.26 nothing new
  deploys meanwhile: its CI is refused (`app_in_custody`, or
  `owner_inactive` from the moment the account can no longer sign in until
  the move), but for a rebuild of the commit the app serves. When the
  account is reactivated, the person signs in again and each app comes back
  to them, with a `transferred` notice saying it returned; from v0.18.26
  its deploys are then held until they keep its repository or move the app
  to another (the skill's **Held deploys: keep or move the repository**),
  which that notice says. A platform admin may instead
  transfer an app to a new owner for good, and then it does not come back.
  When a member asks why an app's owner changed to an admin, this is
  usually why; the admin side is `inno-fleet-admin`'s.
