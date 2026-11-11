# Transferring an app: the cases and every answer

Read this before a `transfer_app` call, and before relaying its answer. The
skill's `transfer_app` section says who may transfer and what to confirm.

**Held deploys** (from platform v0.18.26). Every transfer holds each moved
app's deploys, every app in `also` included, and so does a transfer to the
owner's own address (one that answers the app is already owned moves
nothing and holds nothing); so does every move into custody, hand-over and
return (`references/custody.md`). No repository changes hands with the
app, so its repository still holds its code: CI's `policy` job and every
deploy step refuse new code with `deploys_held`, on every push (the
owner's preflight included), and the panel's redeploy of an earlier
release answers the same. A rebuild of the commit the app serves still
deploys while the app's live release tag names that commit (the skill's
**`rebuild_app`**). The answer names the repository and the hold, the
recipient's notice tells them to keep it or move the app, and the previous
owner's says the new owner does. `app_status` prints a `Deploys held since
...` line. Only the app's owner lifts the hold, with `register_app`, once
their owner row is pinned to their account: by keeping the bound
repository, or by moving the app to one they control
(`inno-manage-app`'s **Held deploys: keep or move the repository**). An
admin who does not own the app cannot: their keep call answers who can,
and a move call answers `name_unavailable`. A keep is final, since an app
whose deploys are not held cannot be moved, so the owner decides before
calling. Say
in the confirmation that once the recipient keeps the repository, whoever
can push a release tag to it controls the app's code, the previous owner
too while they keep write access to it, so a repository in the previous
owner's account is best moved. The audit rows are `deploys_resumed` (a
keep) and `repo_rebound` (a move) (`references/audit-rows.md`).

**A linked set, and a public app:**

- **`also`** moves up to nine more apps in the same call, as one set: the
  set moves whole or not at all, under every app's lease, and the
  recipient's active-app limit counts every app of it that is not stopped.
  Each app in `also` must share a data link with `app` itself, as its
  source or its consumer (a live link, or a revoked one whose binding is
  still deployed in a function-shaped consumer), else the call is refused
  `also_not_linked`: an app
  linked only to another app of `also` is not admitted, so name the app
  the others link to as `app`. A link between two apps of the set is kept,
  and nothing is rebuilt for it; a link to an app outside the set follows
  `link_transfer_blocked` below. Use it for the two-app pattern's pair (a
  public site and its editor) and whenever an owner's linked apps should
  stay together. An app in `also` the recipient already owns, or `also` on
  a transfer to the owner's own address (which re-points that one app
  only), is refused `bad_request`.
- **An app's audience does not change with its owner**: a public app stays
  public and an internal one internal. So the recipient's settings are
  read, under the leases: an app of the set that is internal while
  `access.allow_internal` is false for it under the recipient, or public
  while `access.allow_public` is, is refused `audience_disallowed`. Allow it
  for the recipient with `set_config`, or narrow the app first with
  `set_app_access`: the admin's choice.
- **A public app's transfer needs `accept_guardrails: true`**, alone or in
  a set, after the review of what the public app reaches (`inno-manage-app`'s
  widening review, read for public); without it the call is refused
  `guardrails_not_accepted`. Run the review with the admin, get their
  explicit yes, then pass it; never pass it on your own. A guardrails
  conflict the review finds for the public app is a HARD STOP, as for a
  widening: name the policy line, and do not ask for the yes or pass the
  acceptance unless the admin makes an explicit exception for it (never
  assume one). The other ways forward: narrow the app first with
  `set_app_access` (the transfer of an app that is not public needs no
  acceptance), or have its owner change it. The platform
  records it on each app's `app_transferred` row (`accepted_guardrails`,
  `accepted_by`, and `moved_with` naming the set's other apps), and each
  public app's transfer tells the platform admins (an admin `transferred`
  entry).

**A previous owner who is not kept** loses their member row in that write;
after it their stored connections for the app are deleted and, for an MCP
app, their token grants for it revoked. Those later steps can fail without
undoing the transfer, and the answer then says so:

- if the connections delete fails, `list_user_connections` with their
  address and the app shows what is left, and `disconnect_user_connection`
  removes each;
- if the grant revocation cannot be verified, the answer says so. On a
  members-only app their tokens are refused at the front door's next
  introspection all the same, since their row is gone. On an internal app
  their tokens keep working, since an internal app admits everyone who
  signs in, and on a public app anyone reaches it with no token at all.

They keep their panel and browser app sessions until `revoke_sessions` ends
them (the skill's `revoke_sessions` section).

**A transfer to the owner's own address** re-points an app whose owner's
address has passed to another person (the admins' `identity_reassigned`
notification names such an app, **Fleet-wide reads**), in either
membership mode. In scim mode the owner row moves to the account the
identity provider pushed for the address, once a sign-in has pinned it;
where there is none, and always in jit mode, the owner row is left for the
address's next sign-in to pin. `get_platform_docs` section 16 (What the
tools do in detail) lists every outcome; a read that fails refuses it
`upstream_error`, with the pin as it was. The mistyped-address repair below does not apply,
since the address is the owner's own. Confirm with the admin first: it
takes the app from the account that owned it, which may be the same person
under a new address. From platform v0.18.26 the re-point holds the app's
deploys (above), and when the owner row was pinned to an account, it ends
every session that account holds, everywhere, and revokes every MCP grant
it holds, in the same move; the answer says so (`That account's sessions
were ended everywhere ...`, with how many grants were revoked, or that they
could not all be). The address's new holder then signs in to the platform
and keeps the repository or moves the app.

What to do with its refusals and answers:

- `email_domain_not_allowed` (about the recipient; the previous owner is
  never one) when the instance lists allowed email domains and the address
  is outside them (a listed domain's subdomains are inside; the list is the
  manifest's `identity.allowedEmailDomains`, as the skill's admin list says).
- `app_limit_reached` when the recipient is at their active-app cap, which
  counts unless the app is stopped. Its message normally names the remedy,
  raising the recipient's `apps.max_active` at user scope with
  `set_config`. Do NOT offer to stop the recipient's apps for them.
- **A recipient with no account** is not refused. In scim mode the address
  is checked, read-only, against the accounts the identity provider pushed,
  and the transfer still lands, with a `WARNING:` when no active pushed
  account holds it; in jit mode nothing is checked and no warning comes. If
  the address is mistyped, transfer
  the app again to the right one, then run `revoke_access` on the mistyped
  address, which that second transfer leaves on the member list as the
  previous owner; if their account is still being created, they can reach
  the app once it exists. If the check could not be made, the answer says
  the address was not checked.
- `app_busy`: retry once after a moment, never in a loop.
- `link_transfer_blocked`. Data links are same-owner only, so a transfer has
  to revoke every link that touches the app. While any of those links still
  has a deployed binding (a live link, or one revoked from a function-shaped
  consumer no deploy of which begun after the revocation has completed, so a
  deploy still in flight still blocks; a container-shaped consumer's host refuses a revoked
  link at once, so its revoked link does not count), the transfer is refused
  with `link_transfer_blocked`, naming each `consumer->source` pair. There
  are two ways forward and the choice is the admin's: unlink with
  `unlink_app_data` and redeploy each function-shaped consumer, then
  transfer (for one of those, unlinking alone does not clear the block: a
  redeploy of the consumer begun after the unlink does, once it has
  finished), or call again with `force: true`. **Never add `force: true` on
  your own.** Explain what it does, name the affected apps, and get an
  explicit yes.
- **What `force: true` does.** Its argument's description says how it
  revokes those links and rebuilds each affected function-shaped consumer;
  a container-shaped consumer is not rebuilt, since its host refuses the
  revoked link live. Each consumer's owner is also notified
  (`link_revoked`). Say before the yes who keeps access, and for
  how long: a container-shaped consumer is cut off within 60 seconds by
  its host's live link check (its reads of
  the database and the files then fail `link_revoked`), but a
  function-shaped consumer keeps read-write access to the other app's
  database and files until its rebuild finishes. For a function-shaped
  consumer another account owns, the source's owner and the admins are told
  too (`cross_owner_link_revoked`); the answer says which. If it says
  `REBUILD NOT DISPATCHED` for an app, that app keeps its binding until a
  deploy of it completes: the hourly check tries a function-shaped one again
  a day later, and a redeploy by hand (its owner's tag, or `rebuild_app`)
  cuts it sooner. Tell the admin and that app's owner. From platform
  v0.18.26 a consumer this transfer moves has its deploys held, so its
  rebuild deploys only while its live release tag still names the commit
  it serves; once the tag names another commit the rebuild fails at its
  `policy` step, and the binding stays until the recipient keeps or moves
  the repository and releases, or an admin stops the app.
- `link_containment`: `force` does not override it. Grant the recipient
  access to the named source app first, move the source with the app in
  `also` (when that source shares the link with `app` itself), or unlink
  and redeploy the consumer (starting it first if it is stopped), then
  transfer. A source that is internal or
  public holds everyone who signs in, so only a members-only source
  refuses. The source must hold the same person as the recipient (the same
  account when both rows are pinned, else the same address), and on a
  transfer to the owner's own address, a source owned under that address by
  another account is named to re-point first, with `transfer_app` to the
  same address on that source.
- **A refused transfer leaves nothing to clean up**: the recipient's
  member-list row is written only in the write that makes them the owner.
- **Outcome unknown.** Rarely the answer says the platform "could not tell
  whether the transfer ... was recorded". Nothing was undone. Check the owner
  with `app_status`, and finish by hand the steps the answer lists.
- A data export the previous owner started and that has not finished fails
  once ownership moves; the new owner starts a fresh one if they want it.
