# Custody and the break-glass

Used from `inno-fleet-admin` when a deactivated owner's apps, their return,
or an `identity.initialAdmins` address the identity provider deactivated
comes up: what custody does, how the apps come back, the cases that are an
admin's, and what the break-glass addresses keep. All of it is scim
mode's (`inno-fleet-admin`'s **Membership mode and SCIM provisioning** says
how to tell which mode runs), except the hourly return in jit mode.

## Custody: a deactivated owner's apps

In scim mode, when the identity provider pushes a deactivation or a delete
of an account, and for each person the switch to scim blocks, the platform
at once ends that person's panel and browser app sessions, refuses their MCP
tokens at the next check, and moves every app they own into **custody**: the
owner becomes the custodian, the first address in `identity.initialAdmins`.
The moves go a group of linked apps at a time, so no move splits a live data
link, and each starts only while a budget of 600 statements lasts: what a
request cannot finish, the next hourly pass does. Each app keeps running, with its audience (a
public app stays public), its data links, its member list, its deploy state
and its idle clock. A delete also removes the person's stored connection
credentials, their key wraps and their key (from platform v0.18.4, by
subject: the person's own, never a later holder's of the address). A push tells the admins once per person
(`account_deactivated`), naming the apps moved and any left for the hourly
pass, which moves those; the switch tells them once, with
`provisioning_changed`, in place of a notice per person.
While an app is in custody the custodian is its owner (`app_status` and
`list_apps` name them), and the hourly audience pass judges it for the
person it is held for. An app is in custody while it carries the custody
mark, whoever owns it. From platform v0.18.4 custody is visible: `app_status`
has a `Custody:` line and a `custody` field (`held_for`, the address it
returns to, null when no member row names one; `pending`, true while the
person has no pinned account), and `list_apps` marks the app `[IN CUSTODY]`.
The mark has a kind (`custody_kind`: `email` or `sub`, null only for a mark an
older build wrote), which `export_platform_backup` carries beside
`custody_of`. The custodian's own member row on it lasts exactly as
long as custody, and a grant the custodian held before custody stays.

**Custody follows `identity.initialAdmins`.** The hourly pass hands any held
app that the first address in `identity.initialAdmins` does not own to that
address, so changing the list's first address strands nothing. The app keeps
its mark and still returns to the person it is held for, and the admins are
told once per pass (`provisioning_changed`). A mark left by an older build is
held and returned the same way.

The apps come back by themselves. When the account is reactivated or pushed
again, or at the sign-in that pins it, each app returns to the person it is
held for, its owner row as it was, and its owner is told (`transferred`);
the admins once (`account_reactivated`). Linked apps return together. A
return inside a request runs under the same budget of 600 statements, and
the apps it leaves go back at the next hourly pass, which the admins' notice
names. The person's sessions do not come back: they sign in again. In jit
mode the hourly pass returns every app in custody, which is how a switch
back to jit unwinds it. Three cases are the admin's:

- **A transfer ends custody.** `transfer_app` of an app in custody clears
  its custody mark and the custodian's custody member row, so it does not
  return. From platform v0.18.4 its answer says so ("It was held in custody
  for <address>: this transfer ended that custody") and its `app_transferred`
  row carries `custody_ended_for` and `custody_kind`. Read `app_status` first:
  its `Custody:` line names the person the app is held for. Decide with the
  admin whether that person is gone for good before transferring one to a new
  owner.
- **`revoke_access` will not remove the person an app is held for.** It
  refuses them `owner_not_revocable`, as it refuses an owner, and its link
  cascade leaves a linked app held for that person as it is, with a warning
  line naming it. A platform admin's `transfer_app` comes first, or
  `stop_app`.
- **An app that cannot find its way back** (it is held for an account that
  no member row of the app names any more) stays in custody until an admin
  moves it with `transfer_app`. `revoke_access` no longer removes that row,
  so the hourly warning the platform logs for it is a backstop for a row
  removed before v0.18.1.

**A reused login** (from platform v0.18.2). When the identity provider
gives a login to someone new, the new holder gets a fresh account, and the
earlier holder's account stays deactivated and pinned to them, so the apps
held for them stay in custody and the new holder is not blocked. A person
removed from the provider's app and assigned again is matched by their
`externalId`, and their old account, deactivated after they had signed in,
is revived unpinned (`account_updated` with `revived: true` and
`unpinned: true`). The revive also ends that earlier person's sessions
and revokes every MCP grant they held (`sessions_revoked`), so a re-added
person signs in again and reconnects their MCP clients once. The apps held
for them return when they next sign in, since that sign-in pins the account
to them again; only a sign-in pins, never a push. On a provider whose `externalId` names a login rather than a
person, someone new may be matched instead: their sign-in pins the account
to them, and the earlier holder's apps stay in custody, held for that
earlier holder. A provider that sends no `externalId` cannot be matched
this way, which is a known limit: such a person gets a fresh account, and in
scim mode stays blocked until an admin steps in. When someone new signs in
at the address of a held app's person, the custodian's notice
(`member_reassigned`) names the remedy: `transfer_app` of the app to the
address, to hand it to the address's new holder instead.

**Blocking by subject** (from platform v0.18.2). When a push or the
switch blocks a person whose address now belongs to someone
else, it ends that person's sessions through their subject and leaves the
address's panel sessions alone, since they are the new holder's. The audit
row carries `panel_sessions_kept: true`.

## The break-glass

Every address in the manifest's `identity.initialAdmins` can sign in in
scim mode whatever the identity provider pushed, so a misconfigured provider
or a stolen SCIM token can never lock the instance's first admins out, and a
switch's preview never counts one. Admin standing still needs the address's
row in the admin list: the list seeds only an empty table, so such an
address whose row was revoked signs in but is not an admin until
`grant_admin` writes the row again. A push that deactivates or deletes such
an address changes nothing but the record (`account_blocked` with
`exempt: true`) and the admins' `account_deactivated` notice: its sessions
stay and its apps do not move. To offboard one, an operator removes it from
`identity.initialAdmins` in the manifest and deploys; no push and no tool
changes that list.
