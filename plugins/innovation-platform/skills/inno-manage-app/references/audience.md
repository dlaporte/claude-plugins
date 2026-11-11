# Changing who may reach an app

Read this before a `set_app_access` call: a widening takes the steps below
in order, and a narrowing is said to the user before the call. The skill's
`set_app_access` section defines the three audiences. The last section says
what becomes of a data link that joins two owners' apps.

## Widening: the steps

1. **Public needs an anonymous app.** Asked for an identity-aware app, the
   tool answers `audience_needs_anonymous` alone, naming the two-app
   pattern. Check the app's identity with `app_status` first. If the user
   wants this app's content public, or a public site with an editing area,
   read the `inno-new-app` skill's `references/two-app-pattern.md`: a new
   anonymous app becomes the public site, and this app its editor.
2. **Run the review**, and write it into your reply as a structured section,
   never a one-line summary:
   1. what the app stores: its schema and its files (for an app already in
      use, offer `export_app_data` so the owner can read what is there);
   2. what each new caller will see and can do: every page, query and tool
      the wider audience reaches;
   3. every Variable (`list_app_variables`) and the upstream it spends: a
      key a wider audience can spend needs the limits `get_app_security` §5
      sets;
   4. its data links in both directions (`list_app_links`);
   5. for internal: that what a signed-in non-member sees and can do is
      meant for anyone in the institution, per the **Internal apps**
      section of `get_guardrails`;
   6. for public: the **Public apps** section of `get_guardrails`, and that
      what is published cannot be withdrawn from crawlers and caches, even
      by a later narrowing;
   7. what current users will notice.

   A widening never changes the app's code. An internal app's non-members
   arrive signed in and carry no group (the identity helper's `member` is
   false), so app code that serves only members refuses them: check the
   code before promising that widening lets everyone in. If the app changed
   since `inno-safety-preflight` last ran, run it again for the target
   audience.
3. **One precheck call:** `set_app_access({ app, audience })`, with no
   `accept_guardrails`. A widening call is also its complete precheck: every
   requirement it does not meet comes back at once as one refusal,
   `widening_requirements`, whose message lists each as `[code] sentence`,
   in a fixed order. Read it entry by entry:
   - `[audience_disallowed]`: the target's setting (`access.allow_internal`
     or `access.allow_public`) does not allow it for this app or its owner.
     Only a platform admin can change that, with `set_config`: offer to
     draft the request (the skill's **Asking a platform admin**). Never work
     around it with mass `grant_access`.
   - `[link_containment]`: the app reads a source, through a live data link
     or a revoked one whose binding is still deployed, that does not reach
     as far as the target, so the wider audience would reach that source's
     data and files. The sentence names each source and its remedy: widen
     the source first (its own review), or unlink with `unlink_app_data` and
     redeploy this app; for a revoked link, widen once a deploy of this app
     made after the revocation has landed.
   - `[owner_inactive]`: the owner's account can no longer sign in, so a
     platform admin transfers the app to an active owner first.
   - `[guardrails_not_accepted]`: no acceptance was passed. **When it is the
     only entry**, every other requirement is met, and that is the cue for
     the acceptance step, since the review has already run (step 2). With
     any other entry beside it, fix what the other entries name (or ask for
     it) and run the precheck again; never accept past an unmet requirement.
4. **The acceptance.** A guardrails conflict the review found for the new
   audience is a HARD STOP: it bars this widening, as
   `inno-safety-preflight` says. Name the guardrail line the app conflicts
   with for that audience, and the ways forward: change the app and run the
   review again, keep the narrower audience it has, or ask a platform admin
   for an explicit exception (you cannot grant one; the skill's **Asking a
   platform admin** says where the request goes). Do not ask for the
   acceptance or pass `accept_guardrails: true` until the app is changed or
   that exception is granted. With no conflict, show the user the review's
   conclusions and ask for an explicit yes that the app follows the
   guardrails for its new audience.
   Only then call `set_app_access({ app, audience, accept_guardrails: true })`.
   Never pass `accept_guardrails: true` without the review and that yes.
5. **Relay the answer.** It says the app was widened and when that takes
   effect. A widening to **public** also tells the platform admins, and turns
   unusual-usage detection (`anomaly.usage_enabled`) on for the app unless a
   setting already decides it; the answer says which. Tell the owner both.

`app_busy` on a widening can also mean a source the app reads is changing:
retry once.

## Narrowing: what to say before the call

- **What persists**: the named member list, the app's data and files, its
  variables, and its own links to the sources it reads.
- **Links it revokes**: this app's data link to every consumer it no longer
  contains (one that reaches further than its new audience, or a
  members-only one admitting someone this app's list does not hold). The
  result says which links went and why, and each consumer's owner is told.
  Relink afterwards only a consumer this app contains again
  (`link_app_data`). When the result names a consumer's member listed here
  for another account, the fix is the re-share in
  `references/address-changes.md`. A link the narrowing could not revoke
  stays live and is named in the result with the `unlink_app_data` call
  that removes it: relay that, and say that the hourly containment pass
  revokes it within the hour if this app still does not contain that
  consumer, which makes unlinking now optional.
- **A function consumer it cuts is narrowed and rebuilt with it.** A
  function-shaped consumer (`function`, `mcp-function`) whose link a
  narrowing revokes for reach is rebuilt by the platform, whoever owns it.
  In the same step, every function-shaped consumer wider than this app's
  new audience is narrowed to that audience, whether its link to this app
  goes now or went earlier with its binding still deployed, so its wider
  audience loses this app's data and files when this app's does. Its owner
  widens it again, with the whole review and acceptance, once the rebuild
  (or a redeploy) of it has landed; until then a widening of it past this
  app's audience is refused `widening_requirements`, with `link_containment`
  among its entries. The result, and that
  owner's notice, say which.
- **Published content is not withdrawn.** Narrowing a public app does not
  take back what search indexes, archives and caches already hold.
- **What people meet**: someone the app no longer admits is sent to sign in
  or shown the "No access" page, and a page already open gets errors on its
  background requests until it reloads.

## Data links across owners

A data link joins one owner's apps (`link_app_data` refuses any other pair),
and the hourly containment pass revokes a live link whose two apps no longer
have one owner (a sign-in pinned their owner rows to different accounts, or
a transfer step was lost). When the pass, a narrowing, `unlink_app_data` or
a forced `transfer_app` revokes the link of a function-shaped consumer
another account owns, the platform rebuilds that consumer to remove its
binding, and the result or notice says what was done (`set_app_access`'s
description gives the whole rule, including a stopped consumer and one never
deployed). A consumer whose deploys are held (from platform v0.18.26, as
the app a forced transfer moved is) is rebuilt the same way, and that
rebuild deploys only while its live release tag still names the commit it
serves (the skill's **Held deploys: keep or move the repository**). When
a rebuild could not be dispatched, a platform admin can run
`rebuild_app` sooner. Relay it; the consumer's owner redeploys (`inno-ship`)
only when the answer says to.