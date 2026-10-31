# Custody and the break-glass

Used from `inno-fleet-admin` when a deactivated owner's apps, their return,
or an `identity.initialAdmins` address the identity provider deactivated
comes up: what custody does, how the apps come back, the two cases that are
an admin's, and what the break-glass addresses keep. All of it is scim
mode's (`inno-fleet-admin`'s **Membership mode and SCIM provisioning** says
how to tell which mode runs), except the hourly return in jit mode.

## Custody: a deactivated owner's apps

In scim mode, when the identity provider pushes a deactivation or a delete
of an account, and for each person the switch to scim blocks, the platform
at once ends that person's panel and browser app sessions, refuses their MCP
tokens at the next check, and moves every app they own, as one set, into
**custody**: the owner becomes the custodian, the first address in
`identity.initialAdmins`. Each app keeps running, with its audience (a
public app stays public), its data links, its member list, its deploy state
and its idle clock. A delete also removes the person's stored connection
credentials. A push tells the admins once per person
(`account_deactivated`), naming the apps moved and any left for the hourly
pass, which moves those; the switch tells them once, with
`provisioning_changed`, in place of a notice per person.
While an app is in custody the custodian is its owner (`app_status` and
`list_apps` name them), and the hourly audience pass judges it for the
person it is held for.

The apps come back by themselves. When the account is reactivated or pushed
again, or at the sign-in that pins it, each app returns to the person it is
held for, its owner row as it was, and its owner is told (`transferred`);
the admins once (`account_reactivated`). Linked apps return together. The
person's sessions do not come back: they sign in again. In jit mode the
hourly pass returns every app in custody, which is how a switch back to jit
unwinds it. Two cases are the admin's:

- **A transfer ends custody.** `transfer_app` of an app in custody clears
  its custody mark, so it does not return. Decide with the admin whether the
  person is gone for good before transferring one to a new owner.
- **An app that cannot find its way back** (it is held for an account that
  no member row of the app names any more) stays in custody until an admin
  moves it with `transfer_app`.

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
