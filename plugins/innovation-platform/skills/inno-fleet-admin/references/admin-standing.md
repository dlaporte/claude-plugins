# Who is a platform admin

Read this when someone's admin standing is in question: before granting or
removing an admin, when the admin-only tools are missing, or when the
membership mode or an account's status bears on who is an admin.

People sign in through the instance's identity provider, which the
`Identity provider:` line of `get_platform_status` names, followed by the
instance's **membership mode**, the platform setting `auth.provisioning`
(the skill's **Membership mode and SCIM provisioning**):

- `membership jit`, the default and every instance's mode after its
  upgrade to platform v0.18.0: anyone the identity provider lets sign in is
  a member. The platform cannot learn that an account was suspended or
  deleted there, and the line goes on to say so and to name the settings
  that bound how long such a person keeps access. A delete the provider
  pushes over SCIM ends their way in through an app's group at the next
  decision, and the line says so.
- `membership scim`: the identity provider pushes its accounts to the
  platform over SCIM, and only an active pushed account may sign in, beside
  the break-glass addresses (`references/custody.md`). The line counts
  the accounts pushed by state and gives the last push.

When you need to name the identity provider, use that line's name, never
another product's; until the user shows fluency, "your organization's
sign-in" is enough, and "who the platform lets in" says more to most
people than the mode's name.

The platform's own admin list decides, and `list_admins` shows it. An admin
is someone on that list whose account can still sign in, checked through
the one account-status answer every tool uses, held for
`auth.status_check_minutes`. So:

- In scim mode, an admin whose pushed account the identity provider
  deactivates or deletes keeps their row but loses the powers within that
  window, and reactivating the account restores them; an
  `identity.initialAdmins` address is the exception (`references/custody.md`).
  In jit mode the platform cannot learn of a suspension, so an admin keeps
  the powers until removed with `revoke_admin`, or until their sessions and
  grants end (the lengths the `Identity provider:` line names; from
  platform v0.18.27 `revoke_sessions` ends both at once).
- A SCIM token is no admin standing and outlives it. From platform
  v0.18.27, when `revoke_admin` ends the account's admin standing, its
  answer names each live SCIM token the address, or the row it was shared
  as, created ("<email> created SCIM token <id>, which stays live: if the
  identity provider pushes with it, create a replacement
  (create_scim_token, or the panel's Identity tab) and paste it there, then
  revoke it with revoke_scim_token."), and `admin_revoked` records
  `scim_tokens_live`. An account still an admin through another row names
  none.
- When the platform cannot read an account's status (a read of the mode or
  of the pushed accounts failed), admin powers fail closed: an admin whose
  status is unknown is not an admin for that call. An admin-only tool then
  answers that the tool is not found (an error, not `forbidden`), a shared
  tool's fleet form answers `forbidden` or narrows to your own apps and
  notices with no error (the skill's **Authorization summary**), and none of it is a lost standing: retry
  later, and reconnect once the status reads again. A client that connects
  during such an outage is given a member's tool list, with no admin-only
  tool in it, so reconnect then too.
- No group at the identity provider ever makes anyone an admin. Admin
  standing is the platform's own admin list: `identity.initialAdmins` seeds
  it, and `grant_admin` and `revoke_admin` change it (in scim mode,
  deactivate the account at the identity provider to end an admin's
  sign-in). The manifest key `naming.adminGroup` is retired from platform
  v0.18.8: an instance's `validate` refuses it and says to delete the key.
  An admin group at the identity provider, if one still exists, changes no
  one's standing in either direction.
- Each admin row is pinned, as a grant is, to the identity provider
  account that holds its address (at grant
  time when the platform can resolve the address to one account that has
  signed in at it, in scim mode, else at the address's first sign-in), so an address that passes to another person does
  not take the standing with it. The admins get an `identity_reassigned`
  notification (`references/admin-notifications.md`), and the fix, if the new holder should
  be an admin, is `revoke_admin`, then `grant_admin`, for the address.
