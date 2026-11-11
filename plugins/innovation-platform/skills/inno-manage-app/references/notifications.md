# Notifications worth acting on

Read this when a notification about one of the user's apps appears, in
`list_notifications` or an email, and the user wants to know what to do. The
skill's **Notifications** section says what the feed is and how to mark
entries read.

Stages worth acting on when one appears: `first_deploy_due`,
`respin_failed`, `auto_restarted`, `auto_restart_failed`, `link_severed`,
`link_revoked`, `degraded`, `usage_anomaly`, `quota_horizon`,
`connection_expired`, `connection_locked`, `connection_refused`, `unlinked` /
`relinked`,
`transferred`, `access_changed`, `shared`, `exported`, `member_reassigned`,
`cross_owner_link_revoked`, `host_upload_blocked`. What to do on eleven of
them:

- `first_deploy_due`: a registered app has not completed its first deploy,
  and the entry gives the date and time it is deleted unless one completes
  first. To keep it, ship a release (`inno-ship`); if it is no longer
  needed, nothing is required, and the repository is never touched. A
  start of a stopped app that never completed a deploy sends it too, with
  the new date, or, for a pinned app, with none: it is not removed.
- `access_changed`: the app's audience changed, and the entry says who
  changed it and why. Someone other than the owner widened or narrowed it,
  the hourly pass narrowed it (its setting no longer allows the audience,
  or, for a public app, its owner can no longer sign in), or a source it
  reads was narrowed and narrowed it too: then the entry says why, its
  `link_revoked` entry says whether the platform rebuilds it or the
  owner redeploys, and the owner widens it again, with the review, once that
  rebuild or redeploy has landed (`references/audience.md`'s **Narrowing**).
- `member_reassigned`: an address with access now signs in as a different
  account than the one its access is pinned to. The entry names the address
  and the re-share: `references/address-changes.md`. From platform v0.18.9,
  on a members-only app whose identity provider group still admits the new
  account, the entry says so and names the group: a re-share (`revoke_access`,
  then `grant_access`) then gives the new holder a way in that outlasts the
  group, and removing them from the group at the identity provider ends
  theirs. From platform v0.18.11, on an internal or public app the entry says
  instead that the audience still lets the new account in (an internal app as
  a non-member whenever it can sign in, a public app without any sign-in),
  with the same re-share to make them a member; before that release such an
  entry named the group, or said that account is refused. For an
  app held in custody for the address's earlier holder, `revoke_access`
  refuses the person it is held for, so the remedy is an admin's
  `transfer_app` of the app to that address, which hands it to the address's
  new holder.
- `transferred`: the app's owner changed, and the entry says how: a
  platform admin transferred it to or from the reader, or it came back from
  a platform admin's custody once its owner's account could sign in again
  (`references/deactivation.md`). An app that came back kept
  running while it was away, with its audience and its data links. On a
  platform before v0.18.26 nothing needs redoing. From v0.18.26 the move
  held the app's deploys, and the entry says so: the new owner's, or the
  returned person's, says its repository still holds its code and names
  the `register_app` call that keeps it, or the move to another repository
  they control, to make before the next release (the skill's **Held
  deploys: keep or move the repository**). The previous owner's says the
  new owner keeps or moves it, so it asks nothing of them.
- `degraded`: the owner's app is failing requests. Two senders: the
  error-budget burn (the last hour's failures against the availability
  target), and the post-deploy watch (failures since the latest deploy,
  against the rate before it). The stopgap is the panel's app page,
  **Overview, then Releases**: any recent release the Releases card
  lists, but the running one, redeploys with one click while the app is live. It goes back through the full gates and deploys
  only if they pass today, it runs against the app's current data (an app
  that changed how it stores things may misbehave), and the next release tag
  supersedes it, since there is no pin to a version. Or fix forward with a
  new release (`inno-ship`). The redeploy is the panel's alone: no tool
  does it, and `rebuild_app` is the admin's.
- `connection_expired`: a person's stored credential for one of the app's
  backends was removed (it expired or was revoked, could not be opened,
  their encryption key was reset, or the connection's endpoints changed),
  so they connect again from the link the app gives them.
- `connection_locked`: the person's stored credential still exists, but
  their MCP client's authorization cannot open it. They re-authorize the
  connector in their MCP client (in Claude: `/mcp`, then re-authenticate
  that server), the fix that lasts; reconnecting the backend does not fix
  it for good (`inno-add-connection` says why). It comes at most once a day per app,
  under its own email setting, `notify.email.connection_locked`.
- `connection_refused`: a backend refused to renew a person's stored
  credential for one of the app's connections in a way no retry fixes. It
  refused the app's registered client or its request (an expired or rotated
  client secret, a disabled client, a withdrawn scope), not the person's
  credential, which the platform keeps. The owner fixes the connection's
  settings (`set_app_connection` or the app's Connections tab); the people
  need do nothing. It comes at most once a day per connection, under its own
  email setting, `notify.email.connection_refused`.
- `link_revoked`: a data link this app used was revoked. The entry
  says whether a rebuild was dispatched, whether the owner has to redeploy
  (for an owner that is `inno-ship`), or, for a stopped app, that the platform
  rebuilds it after it next starts. For an app that has deployed, it also
  says that the app's code that reads the source's database or files fails
  (a function-shaped app's once it is rebuilt, since its link bindings are
  gone; a container-shaped app's within about a minute, since those reads
  then answer `link_revoked`): so a rebuild is not the end of it. Remove that code, or
  link the data again with `link_app_data` where the rules allow, as the
  entry says. For an app whose deploys are held (from platform v0.18.26),
  a dispatched rebuild deploys only while its live release tag still names
  the commit the app serves; otherwise it fails at its `policy` step, and
  the binding stays until the owner keeps or moves the repository and
  releases (the skill's **Held deploys: keep or move the repository**).
  Notices sent before platform v0.17.12 are stored under
  `link_rebuild_pending`, so a `stage` filter of `link_revoked` does not
  find them: filter by app instead.
- `cross_owner_link_revoked`: a function-shaped app another account owns read
  this app's data through a link that was revoked, and the entry says what
  the platform did to remove its binding (`references/audience.md`'s
  **Data links across owners**). When it says the rebuild could NOT be dispatched, a platform admin
  can run `rebuild_app` on that app sooner; after a dispatched one,
  `rebuild_app` refuses `dispatch_in_flight` for an hour, so the entry does
  not name it. When the entry reports a rebuild dispatched or one that could
  not be, it also names what a platform admin can do if that app's rebuilds
  never land (its owner can cancel each run): stop it (`stop_app`, which
  holds only once its owner has spent their self-service starts), transfer
  it (`transfer_app`), or stop it and then purge it (`purge_app` takes a
  stopped app only). Those are an admin's calls: offer to draft the request,
  naming both apps (the skill's **Asking a platform admin**). This bullet and the
  next are the plugin's one home for
  these two notices; `inno-fleet-admin` points here.
- `host_upload_blocked` (container apps): a platform
  release could not upload a new host for the app, because one of its data
  links no longer holds, so the app keeps running on the host an earlier
  release uploaded, and every release leaves it out until this is cleared.
  The entry names the link's problem. Remove that link with
  `unlink_app_data` (the owner or a platform admin can), then run
  `restart_app`, which uploads the app's host from the current release.
  Stopping the app does not clear it. Confirm with the user before
  unlinking, since the app loses its read of that source's data.
