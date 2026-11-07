# The admins' notices

Read this when an admin-only notice appears in `list_notifications` or an
email. `list_notifications` shows an admin every app's feed; the stages below
reach admins alone, and the paragraphs after them say what else the admins
receive.

- `start_requested`: an owner asked for a start. An admin's `start_app` is
  unlimited and does not use the owner's allowance.
- `drift_detected`, about the platform rather than one app:
  `plugin.min_version` is above the newest plugin this platform release
  serves (the newest published one of its major), so no user can satisfy
  it, and the entry names the fix: lower it, publish a plugin release of
  that major that meets it, or, for a floor of a later major, upgrade the
  platform.
- `connection_sink_new_host`: a connection was pointed at a credential
  destination no connection on the platform was using. Check that the host
  belongs to the backend the connection claims to be.
- `naming_changed`, about the platform too: a naming key changed on an
  instance whose apps were registered under the old names. The entry names
  the keys and both ways out, which the skill's **`accept_naming_change()`**
  explains: revert the manifest, or move every app by hand and then accept.
- `identity_reassigned`: an address that owns an app, or is a platform
  admin, now signs in as a different account than the one it was pinned
  to, and that account is refused. There is one entry for each app the
  address owns, and one for its admin row. To give an app to the address's
  new holder, `transfer_app` it to that same address (`references/transfer.md`'s **A transfer to
  the owner's own address**); to make them an
  admin, run `revoke_admin`, then `grant_admin`, for the address. Neither
  happens by itself, and until then the account it was pinned to keeps the
  app or the standing under any address it signs in with, so confirm with
  the admin who should have it first. One more entry, about the platform
  rather than one app, says the address now signs in as a different
  account than the one the identity provider pushed for it, which scim
  mode refuses: no tool settles that one. It is settled at the identity
  provider, as the entry says: once the earlier account's change (its new
  address, or its deletion) reaches the platform, the provider pushes an
  account for the new holder, pinned to them at their next sign-in.
  From platform v0.18.2 a login the provider reuses gets a fresh account
  for the new holder: the earlier holder's account stays deactivated and
  pinned to them, and the apps held for them stay in custody.
- `account_deactivated` (scim mode): the identity provider deactivated or
  deleted an account, and the entry names the apps moved into custody and
  any left for the hourly pass; for a break-glass address it says that
  nothing moved and how to offboard it (both in `references/custody.md`).
  The hourly pass sends one too for apps it moved that a push could not.
  A switch to scim sends none: it tells the admins once, with
  `provisioning_changed`.
- `account_reactivated`: the apps custody held for a person returned to
  them, after a reactivation, a new push, the sign-in that pinned their
  account or the hourly pass (which in jit mode returns every app custody
  holds). Each app's owner gets a `transferred` notice too.
- `provisioning_changed`: an admin switched the membership mode; a switch
  to scim names whom it blocked and the apps it moved into custody. From
  platform v0.18.1 the hourly pass sends it too, once per pass that handed
  a held app to the first `identity.initialAdmins` address, naming the
  apps it moved: they return to the person they are held for, as before.
- `edge_mismatch` (from platform v0.17.9): an app's address is out of
  step with its status: it still holds the platform's custom domain while
  the app is stopped or has never deployed, or holds none while the app
  is serving. The hourly edge pass reports it (once, and again after a
  week while it lasts) and never attaches or detaches a custom domain
  itself: only a transition brings the address back in step, and the
  entry names the one for the app's status. A stop detaches the domain
  and holds the address, and a deploy attaches the domain. For a
  never-deployed app the transition is its first deploy, or, for an app
  nobody will ship, `stop_app` then `purge_app`, which deletes it. Prefer
  the first deploy: a stop starts the app's purge countdown and refuses
  its first deploy until a `start_app`, which returns the app to not
  deployed with its first-deploy window started again. For a stopped app,
  leaving it is usually better: the front door answers a stopped app's
  address with the stopped page whichever way a request arrives, so
  visitors see nothing wrong, and the mismatch costs only this notice
  once a week, an `edges_reconciled` row each hour and one of the edge
  pass's 25 apps a run, until the owner's own `start_app` or the app's
  `purge_app`, which detaches the domain, ends it. To end it at once it
  is `start_app`, then `stop_app`: the app serves in between (after a
  vulnerability stop, the vulnerable code), and an admin's start counts
  as the start after a finding, so the owner's own start to release the
  fix is no longer free; a pinned app's stop answers `app_pinned` and
  leaves it serving, so unpin it first (the skill's **`purge_app`** says how)
  and pin it again after the stop, or it counts down to its purge. For a
  serving app it is `rebuild_app`, which redeploys its live release.
  Confirm with the app's owner first, saying what they agree to: the
  deletion of an app nobody will ship, the minutes a stopped app serves
  again and the free start it spends, or a rebuild of a serving app.

Admins also get a copy of each `cross_owner_link_revoked` notice, and see
each app's `host_upload_blocked` notice in the fleet feed (it goes to the
owner alone, and the release run fails on it). The meaning and remedies
of both are `inno-manage-app`'s `references/notifications.md`, the owner's and an
admin's: the stop, transfer or stop-then-purge the first names, and the
unlink then `restart_app` that clears the second. Confirm with the app's
owner before acting on either.

Admins also get their own `access_changed` entry when an app is widened to
public (who widened it, and whether unusual-usage detection is now on:
the skill's **Audiences**) and when the hourly pass narrows a public app whose
owner can no longer sign in (transfer it to an active owner before anyone
widens it again: `references/offboarding.md`'s **Offboarding an owner of public apps**; from
platform v0.18.0 that comes only in the minutes after a switch back to
jit, since in scim mode custody takes such an app instead), and
their own `transferred` entry for each public app a transfer moved, which
stays public.
