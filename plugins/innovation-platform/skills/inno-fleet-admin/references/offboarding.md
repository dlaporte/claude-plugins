# Offboarding someone

Read this when someone leaves, or their access must end everywhere. The
skill's `revoke_sessions` section says what that one tool ends.

**A full offboarding** uses three levers, each with its own reach:

1. **Deactivate the account at the identity provider.** In scim mode the
   provider pushes the change and the platform acts on it at once: their
   panel and browser app sessions end, their apps move into custody
   (`references/custody.md`), and the account check refuses their calls to the
   platform's own tools (`account_inactive`), their MCP access to every
   app, their access to every browser app (whose front door asks the
   platform at every request) and their admin standing, if they had one,
   within `auth.status_check_minutes`. From platform v0.18.27 the block also
   revokes every MCP grant they hold, the platform's and each app's, and
   forgets the approvals their MCP clients remembered (a block before
   v0.18.27 revoked none: `references/custody.md` says what to run after
   the upgrade). From platform v0.18.26 their apps'
   repositories also deploy nothing new from then on (`owner_inactive`
   until the move, then `app_in_custody`), but for a rebuild of the commit
   each app serves. A break-glass address is the
   exception (`references/custody.md`). In jit mode the platform cannot learn
   of the deactivation: the
   person keeps access until their sessions and MCP grants end, at most the
   lengths the `Identity provider:` line names, which `set_config` shortens.
   There the next two levers, and `revoke_admin` for an admin, are what end
   it sooner. From platform v0.18.27 that is one call, `revoke_sessions`,
   which ends their sessions and every MCP grant they hold, plus
   `revoke_access` for each app whose member row should go; before it,
   their MCP grants for the platform and for an app they are not removed
   from ran on to their lengths. The deactivation at the identity provider
   still matters there: someone it still lets in can sign in and connect
   again. In jit mode an owner who leaves also keeps the power to
   deploy to each of their apps from that app's repository until an admin
   stops the app, or, from platform v0.18.26, transfers it, which holds its
   deploys until the new owner keeps or moves the repository
   (`references/transfer.md`'s **Held deploys**).
2. **`revoke_sessions`** ends their panel and browser app sessions now,
   and from platform v0.18.27 every MCP grant they hold too, the
   platform's and each app's, with the approvals their MCP clients
   remembered, so each client they connected must sign in again. Before
   v0.18.27 it touched no MCP token. It reaches no group membership.
3. **`revoke_access` on each app they are a member of** removes them from
   its member list and deletes their stored connections there
   (`inno-manage-app` has its rules). It cannot end a way in through an
   app's identity provider group: that ends when the identity provider
   removes them from the group, or in scim mode deactivates the account
   (lever 1). The answer names an app where a group still admits them. It
   refuses `owner_not_revocable` on an app they own, and on an app in custody that is held for them: transfer it
   first (read its `app_status` `Custody:` line, since a transfer ends
   custody for good), or stop it. A grant pinned to their
   account does not pass with their address to its next holder, but one
   still waiting for its first sign-in would: one more reason to revoke.
   To find every app they are a member of, take `export_platform_backup`
   and filter its member rows (`app_members`) by their address: that
   snapshot holds every member row, and no other tool lists a person's
   apps (`list_apps` names owners, `list_users` only owners and admins).

**An admin who leaves** keeps the SCIM tokens they created live, since a
token is no admin standing and no end of a person revokes it. From
platform v0.18.27 `revoke_admin`'s answer and, in scim mode, the admins'
`account_deactivated` notice name each live one: if the identity provider
pushes with it, replace it there first, then revoke it
(`references/scim.md`).

None of the three stops a removed person reaching a public app: anyone on
the internet reaches one, with no sign-in. And `revoke_access` alone does
not keep someone whose account can still sign in out of an internal app,
which admits everyone who signs in.

**Offboarding an owner of public apps.** `list_apps` names each of their
apps' audience. In scim mode a deactivation moves each public app they own
into custody, where it stays public, and the admins' `account_deactivated`
entry names it. So decide each public app with the admin, best before the
account is deactivated: transfer it to an accountable owner (with
`accept_guardrails` after the review, and its linked editor in `also`),
where it stays public and leaves custody for good (from platform v0.18.26
with its deploys held until that owner keeps or moves its repository);
narrow it now with
`set_app_access`; or stop it and then purge it (`purge_app` takes a stopped
app only; a pinned app is unpinned before the stop, as the skill's
`purge_app` section says). In jit mode the platform never learns that the
owner left, so nothing moves or narrows by itself: narrow or transfer each
one by hand.