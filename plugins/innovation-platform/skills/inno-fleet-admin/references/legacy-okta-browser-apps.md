# Browser apps an earlier release left on Okta groups

Used from `inno-fleet-admin` when an admin finds or fixes a browser app
(`container`, `function`) registered before platform v0.16.5 whose
Cloudflare Access application still admits by its Okta groups: a grant or an
open that does not reach someone, a new owner Access refuses, someone who must
lose such an app now, a `member_drift_detected` or `cutover_undo_failed` entry
in the feed, or an Okta group a purge left in place.

## What such an app is

There is no okta mode: migration 0056 moved every app to the platform's
member list, and no grant, revoke, open or close touches an app's Okta
groups, its Okta rule or its Access policies any more. A browser app
registered before v0.16.5 whose deploy never moved it off its Okta groups
still has an Access application whose `members` policy, and `open` policy
while it was open, admit only the people those groups hold, which nothing
updates now.

To find them: the operator's Access inventory, the read-only command in the
v0.16.8 section of the operator's upgrade guide (`docs/instances/UPGRADING.md`
in the platform's repository; no tool serves it, and the admin plugin's
`platform-upgrade` skill reads it), lists these apps only when it was run
**before migration 0056**, so use the list kept from that run. After the
migration it lists nothing. Without a kept list, that section gives a
fallback query, and in the Cloudflare dashboard (Zero Trust, Access,
Applications) such an app's Access application still has a `members` policy.

## Taking someone off one now

Stop it (`stop_app`), or redeploy it on the newer gateway (`rebuild_app`),
which then refuses them, and do not restart it until its Access policies are
swapped (the fix below).

## The fix, in this order

1. **Redeploy it** (`rebuild_app`, or its owner's next tag) on a gateway of
   capability 1 or more, and check that the deploy finished and that no
   restart followed it. **Do not restart it** with `restart_app` from the
   redeploy until steps 2 and 3 are done, and if the platform's
   auto-restart (`remediate.auto_restart`) is on for it, set it to false
   for that app (`set_config` at app scope) before the redeploy and remove
   that override (`remove_config`) once steps 2 and 3 are done: a restart
   that lands inside the deploy can put the older, capability-0 version
   back. The upgrade guide's v0.16.8 section says how to check.
2. **Add a sign-in policy** to its Access application: an allow policy
   named `signin` whose include is the Login Methods rule for the
   instance's identity provider (the manifest's `cloudflare.accessIdpId`),
   never Everyone.
3. **Only then delete its `members` and `open` policies**, so the
   application is never left with no allow policy.

Keep that order: adding the sign-in policy first opens the app to everyone
who signs in while a gateway below capability 1, which asks nothing, still
fronts it. The other way out is to purge the app and register it again
(`purge_app`, then `register_app`), which gives it a sign-in-only Access
application; a purge deletes its data and its member list, so export the data
first (`export_app_data`) and grant its people again. Either way its owner
then re-grants with `grant_access` anyone who reached it only through its
Okta group. Once fixed, its Okta groups and rule admit no one through any
policy, and they stay in Okta until `purge_app` deletes them by their
recorded ids.

## Old feed entries

`member_drift_detected` and `cutover_undo_failed` were raised only by
platform v0.16.5 to v0.16.7, so an entry in the feed predates the upgrade:

- `member_drift_detected`: a browser app's deploy could not move it off its
  Okta groups, because its member list and its Okta group disagreed. Its
  advice to run the import for the app no longer applies: the app it names
  may still have an Access application that admits by its Okta groups, so
  check, and fix it as above.
- `cutover_undo_failed`: a browser app's move off its Okta groups failed and
  could not be fully undone, and the entry says at which step and what was
  left. Look at the app's Access policies in the Cloudflare dashboard: it
  should end with the sign-in policy alone, as the fix above leaves it.

## Okta groups a purge leaves

`purge_app` deletes only the Okta groups and rule the app's record names, by
id, and an app registered from platform v0.16.5 (an MCP app from v0.16.4)
records none. A recorded group another instance marked is left in place,
which the `app_purged` audit row's `idp_skipped` detail lists. So is a
recorded open group whose open rule the record never named (a registration
before v0.16.5 that stopped part way), since a rule may still assign to it:
its entry's `why` reads "its open rule was never recorded, so a rule may
still assign to it", and it is this instance's own, for the procedure below
to remove with that rule. An open group or rule the record never named stays
in Okta. The operator guide's "Leftover app groups and rules"
(`docs/OPERATIONS.md` in the platform's repository, its Teardown section; no
tool serves it) says how to tell whether one is this instance's before
removing it.
