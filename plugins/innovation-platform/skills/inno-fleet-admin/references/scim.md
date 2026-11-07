# The SCIM token, and switching the membership mode

Read this before `create_scim_token` or `revoke_scim_token`, and before any
change of `auth.provisioning`. The skill's **Membership mode and SCIM
provisioning** section says what the mode is and what `get_provisioning`
reads.

- **The SCIM token** is what the identity provider's provisioning app sends
  with every push, and the most powerful credential the platform accepts:
  whoever holds it can deactivate every pushed account, which in scim mode
  blocks everyone but the break-glass addresses, and can admit a person the
  identity provider signs in to any members-only app by pushing them into
  its group. It can never make an admin. At most two are live at
  once, so a token rotates with no gap: create the new one, have the admin
  paste it into the provider in place of the old one, and once they have
  saved it there (the provider's connection test or its next push uses it),
  read `get_provisioning` once and check that the new token's last use
  moved, which proves a request with it reached the platform, then revoke
  the old one. A third create is refused
  `scim_token_limit`: revoke one first. A provisioning app that sends its
  token field as the whole Authorization header takes the token as
  `Bearer <token>` (Okta's SCIM 2.0 Test App (Header Auth) is one). The
  provisioning app may push groups (Okta: Push Groups on; Microsoft Entra
  ID: assign groups to the provisioning app, and their members are pushed
  as Users). The platform stores each pushed group, its name and its
  members, and lists them (`get_provisioning`'s `groups`, a count, and the
  Identity tab). From platform v0.18.8 a pushed group named
  `<groupPrefix><app>-users` (the manifest's `naming.groupPrefix`; the
  name is matched ignoring ASCII case, nothing trimmed) admits its
  members to that members-only app, beside the app's member list, in either
  membership mode: push one to give a team an app, and see each member's
  way in on the app's `app_status`, as `inno-manage-app` says. A group never
  grants admin. The platform never changes a group: removing someone from
  it at the identity provider ends that way in, and `revoke_access` cannot.
  Instances that share an identity provider use distinct group prefixes, so
  one instance's apps are not named by another's groups; where two already
  share a prefix, push each app's group only to the provisioning app of the
  instance that holds the app. A group named for an app that does not exist
  does nothing until an app of that name is registered, and a purged app's
  group, which a purge never deletes, admits its members to any app later
  registered under the name. Anyone who signs in may register an app, and a
  purged name is held for 7 days, so whoever registers a name a pushed group
  matches admits that group's members and sees their addresses on the app's
  roster: push an app's group to the provisioning app only once the app is
  registered. On Okta, leave Import Groups off: it would pull the groups Okta
  itself pushed back into Okta as new groups. A request naming more than
  about 23,300 members at once is refused (the 1 MiB body limit for groups;
  `/Users` keeps 64 KiB), and fewer fit where the provider adds to each entry
  (Entra a `$ref`, Okta the member's display name). A listed page of groups
  with their members carries at most about 10,000 members, every listed group
  whole, so a provider pages by the `itemsPerPage` the answer gives. `/Bulk`
  and `/Me` still answer 501.
  - **Prefer the panel for a new token.** The Identity tab's Create token
    shows it once, in the admin's own browser. `create_scim_token` returns
    it once in this conversation instead, which puts it in the session's
    transcript: call it only when the admin asks for it here, after telling
    them it lands in this conversation's transcript. Relay the token exactly once, with the base URL, for the admin to
    paste at once; never repeat it, and never write it to a file, a commit,
    a note, a support bundle or a later message, nor ask for it back. A
    token that was not copied cannot be shown again: create another and
    revoke the lost one.
  - **`revoke_scim_token`** takes an id that `get_provisioning` lists; the
    provider's next push with it is refused. An id no live token has is
    refused `scim_token_not_found`. On any suspicion that a token leaked,
    revoke it at once and read what it did with `query_audit`
    (`surface: "scim"`, or `actor: "scim:<token id>"`). Say before revoking
    the only live token that pushes stop until a new one is pasted.
- **The switch to scim** is the step that removes people, so it takes two
  calls, and comes only after the identity provider has pushed its
  accounts:
  1. **The preview.** `get_provisioning` carries it in jit mode, and
     `set_config` of `auth.provisioning` to `scim` at platform scope with no
     `confirm` answers `preview_required` with it. It counts the accounts
     pushed and the people who signed in, how many of those the switch would
     block (each one with no active pushed account, and each app owner not
     signed in at their address, which it counts as
     `blocked_never_signed_in`: one who never signed in, or whose address
     has since passed to someone else), naming
     them, how many apps they own, which move into custody, and whether an admin who can
     sign in remains; it warns when it would block more than a third of
     the people who signed in. Read it with the admin person by person (it
     names at most 50; past 50, the Identity tab's pushed accounts list the
     rest): anyone it names who should keep access is settled at the
     identity provider (assigned to its provisioning app, and pushed) before
     the switch.
  2. **The confirmed switch**, after an explicit yes: `set_config` again
     with `confirm` set to the blocked count the preview reported. A count
     that has moved since answers `preview_stale` with a fresh preview: read
     that one with the admin too, and confirm its count only after another
     yes. Never pass a `confirm` you did not just read from a preview.

  It is refused `initial_admins_required` while the manifest's
  `identity.initialAdmins` is empty (its first address holds the apps in
  custody, so an operator names the first admins and deploys first), and
  `no_pushes_yet` before the identity provider has pushed any account.
  The answer names whom it blocked and the apps it moved into custody. The
  switch blocks people under a budget of 600 statements: past it the answer
  says how many it blocked now, and that the rest are refused at their next
  status check and their apps move at the next hourly pass. A person whose
  address now belongs to someone else is blocked through their own subject
  alone: their sessions end, and the address's panel sessions, which are the
  new holder's now, are left alone (the audit row says
  `panel_sessions_kept`). A person whose
  block failed is named too, and the account check refuses them all the same
  while the next hourly pass moves their apps. Of two switches sent at once,
  the second answers that the mode is already set. Every
  other account reaches the new mode as its held status answer ends
  (`auth.status_check_minutes`). The admins are told
  (`provisioning_changed`).
- **Back to jit** needs no preview, since it widens: `set_config` of
  `auth.provisioning` to `jit`, or `remove_config` of it, applies at once,
  and the admins are told. Confirm it with the admin all the same: from then
  on a deactivation at the identity provider no longer reaches the
  platform. The pushed accounts are kept, and the apps in custody return to
  the people they are held for at the next hourly pass. A switch to the mode
  already set answers that it is already set.
