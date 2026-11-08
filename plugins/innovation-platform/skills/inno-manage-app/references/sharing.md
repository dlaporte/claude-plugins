# Sharing an app: who gets in, and what each answer means

Read this before a `grant_access` or a `revoke_access`, and before relaying
either one's answer. The skill's `grant_access` section says what the two
tools write; this file says what admits a person and what to do with each
refusal, warning and outcome.

**What admits a person** is the app's audience (the skill's `set_app_access`
section), on every type, MCP (`mcp-function`, `mcp-container`) and browser
(`container`, `function`) alike: a members-only app admits a person the
member list holds, or its identity provider group (below) holds, and an
internal app everyone the identity provider signs in, the front door asking
the platform at every request, and a public app admits anyone, with no
sign-in and no question to the platform. A person a members-only browser app
does not admit is refused when they sign in, on the platform's host, with a
"No access" page that names the account they signed in with and links a
sign-out to use another; once the app is shared with that address, they open
the app again. Someone already signed in whom the app stops admitting gets
the front door's 403 "No access" page, which names no account and also links
a sign-out to use another account. The front door shows a 503 "Try again
shortly" page when it cannot get an answer: that is an outage (the platform,
or the sign-in keys it checks people against, could not be reached), not a
revoke, so do not re-grant for it.

**When someone cannot sign in.** The platform signs people in to a browser
app itself, on the platform's host, and what they see (the address bar
during sign-in, about one sign-in a day, and sign-out reaching every app and
the panel, in every browser) is `get_platform_docs` section 5 (Signing in and
out): quote it rather than describing it from memory. Two cases
come up: a "Sign-in not confirmed" page, whose way out is the identity
provider's sign-out that the page links, after which the next sign-in
authenticates afresh; and an app shown inside a frame, which cannot start a
sign-in there: framed by its own page, it shows a "Sign in" page whose link
opens the app in the whole window, and framed by any other page, a
members-only or internal app is refused (the browser shows its
blocked-frame placeholder), since apps never frame each other (contract R3).

**When someone was signed out without asking.** Signing out anywhere, on the
panel or on any app, ends every session that person holds on the platform,
in every browser; and when someone else signs in at a browser where the
person signed in before and never signed out, that signs the person out
everywhere too. Neither is a fault or a revoke: they sign in again, and
nothing about their access changed.

- `email` must look like a real, unquoted email address: the platform
  answers `invalid_email` for anything containing quotes, backslashes, or
  whitespace. Fix the address with the user.
- Membership grants access to the **app**, not to the platform panel: the
  panel shows people only the apps they own.
- When a user's MCP client is refused while they authorize it, keeps asking
  them to approve it again, or never reaches the approval page, read
  `references/mcp-client-approval.md`.

**`grant_access` refusals and warnings:**

- `email_domain_not_allowed`: the address is outside the instance's allowed
  email domains, which the message names. Check the address. If it is right,
  no tool can let it in: the list is the instance manifest's
  `identity.allowedEmailDomains`, which only the platform's operator can
  change, by editing the manifest and redeploying.
- **An address with no account is granted anyway.** In scim mode the
  platform checks the address against the accounts the identity provider
  pushed, and a grant to one with no active account carries a `WARNING:` in
  the result; in jit mode nothing is checked and no warning comes (the
  `Identity provider:` line of `get_platform_status` names the mode). Relay
  the warning, and check
  the spelling with the user: if it is mistyped, `revoke_access` removes it;
  if the person's account is still being created, the grant applies once it
  exists.
- **A grant to someone the member list already holds changes nothing**, and
  says so. It is not an error: tell the user the person already had access,
  and relay anything the result adds about the address passing to someone
  else.
- **A grant to someone the app's identity provider group already admits**
  writes the row anyway, and the result carries a `NOTE:` naming the group
  they already reach the app through. The row is a second way in: it stays
  if the identity provider later removes them from the group. Relay the
  note.
- `link_containment`: this app still reads another app's data the person
  cannot see, through a live link or, for a `function` or `mcp-function`
  app, a revoked one whose binding is still deployed; the message names
  every blocked source, and its own remedy for each. A refused grant
  changes nothing. Grant them access to the named source app first, or cut
  the source off and then grant again: for a live link, unlink it with
  `unlink_app_data` and then **redeploy this app** (the owner's next
  release tag, `inno-ship`, or a platform admin's `rebuild_app`), starting
  it first if it is stopped, since neither reaches a stopped app; for a
  revoked link whose binding is still deployed, there is nothing to unlink
  (`unlink_app_data` answers `link_not_found`), so only redeploy it.
  Unlinking alone is not enough for a function-shaped app: it keeps the
  source's database and files in its deployed code until a deploy begun
  after the unlink has finished. `list_app_links` lists each such revoked
  link apart from the live ones, with its revocation time, and `app_status`'s
  `Data links` line names it as revoked but still deployed, until that
  deploy completes: read either to see whether a redeploy has cleared it.

**`revoke_access` refusals and outcomes:**

- **`revoke_access` removes only a member row, never a group's way in.**
  Two answers say so:
  - A person the group admits and no row names: nothing is removed or
    recorded, and the answer says they reach the app through the identity
    provider group, which only the identity provider changes. To end their
    access, the identity provider admin removes them from that group.
  - A person with a row whom the group also admits: the row comes out, and
    the answer says they still reach the app through the group, so their
    access, MCP token grants, stored credentials and linked apps are
    unchanged. Do not tell the owner the person is off.
  A group's removal of a person ends their access at the next decision (a
  browser app's next access check, an MCP app's next token check), but it
  deletes no MCP grant record or stored connection credential the way
  `revoke_access` does; and a consumer app whose group still admits the
  person keeps them in the cascade. For a members-only source the result
  names such a consumer in a `WARNING:`: it still admits them through its
  group and reads this app's data through a link, so they may still reach
  the data there, and the next hourly containment pass revokes the link
  unless the identity provider removes them from that group first. From an
  internal or public source there is no such promise, since the person
  reaches the data by signing in anyway: a consumer whose member row of
  theirs came out gets a plain `NOTE:` ("Also removed <email>'s member row
  from "<consumer>", which still admits them through its identity provider
  group "<group>"."), and one that held no row gets nothing.
- `owner_not_revocable`: the address is the app's current owner, whose access
  comes from owning it, or the person an app in custody is held for. A
  platform admin's `transfer_app` comes first (**Transferring an app: ask an
  admin**), or `stop_app`.
- **Read the result text, not just the absence of an error, before telling
  anyone the person is off.** It says when the member list did not hold the
  address (a mistyped revoke leaves the member it was meant for in place, so
  check the address), when the account is still a member through another row
  (it names the address to revoke next), and when MCP token revocation could
  not be verified (access still ends within the front door's introspection
  window, as the description says).
- **A wider audience still admits them.** On an internal app they still
  get in by signing in; on a public app anyone reaches it without signing
  in. The member list decides only for a members-only app, so tell the
  owner, and narrow the app (`set_app_access`) if the person must be kept
  out.
- **When the removal bites depends on the app type** (the description gives
  each window). On a members-only app, an MCP app refuses them once the
  front door's introspection cache lets go of their token, and a browser
  app refuses them once the front
  door's held answer runs out; their sign-in session runs on, but it no
  longer gets them in.
- **The revoke cascades** to every app that reads this app's data through a
  link, and on to the apps that read those; the response names the apps it
  removed the person from. A consumer the person **owns** is left as it is,
  and the result names it and says they may still reach the data there: a
  platform admin's `transfer_app` first, or unlink with `unlink_app_data`.
  A function-shaped consumer whose link was revoked while its binding is
  still deployed, and where the cascade would take the person's row, keeps
  its member list, since it no longer links: the platform dispatches its
  rebuild instead, which drops the binding, and the result names it and
  what the rebuild came to (a stopped one is rebuilt once it next starts, a
  dispatch that fails is tried again a day later).
- **A partial cascade is not a finished revoke.** When the response carries a
  `WARNING:` naming apps that could not be updated, relay it plainly, do not
  report the revoke as complete, and run what it names (`revoke_access` on
  that app; a revoke is safe to repeat). When the warning says the cascade
  stopped because it could not read a link or a linked app, do what it says:
  run `list_app_links` on the source app, then `revoke_access` for that
  person on each app it lists as reading the source's data, and redeploy
  each one it lists as revoked but still deployed (the owner's next release
  tag, `inno-ship`), or ask a platform admin to run `rebuild_app` for it
  (the skill's **Asking a platform admin**). Never repair it by hand at the
  identity provider.
  `list_app_links` enumerates the consumers at any time; the audit rows a
  cascade writes are `inno-fleet-admin`'s.
