# innovation-platform changelog

What each release of the plugin changed, oldest first, from 3.0.0.

## 3.0.0

Platform v0.17.0 made a breaking change of its own: its status no longer
carries a sign-out address or gateway capabilities, and the admin tool that promoted the
gateway went with it, so reconnect after that upgrade too. Plugin 3.0.0
follows v0.17.0 and contract 34, where the platform signs people in to
browser apps itself and every app's sign-out link is `/_auth/signout`; the
platform asks for at least 3.0.0 when the instance's admins raise
`plugin.min_version`, as the v0.17.0 release asks.

## 4.0.0

Plugin 4.0.0 follows platform v0.17.2 and contract 35, which give every app
two properties: its **audience** (who may reach it: members-only, internal,
which is everyone who signs in and was called open before, or public, anyone
on the internet with no sign-in), changed at any time and widened only
through the plugin's review and a recorded guardrails acceptance; and its
**identity** (identity-aware or anonymous, whether the app is told who calls),
chosen at registration and fixed. Only an anonymous app can be public. Three
tools take new input (`set_app_access` takes `audience` and
`accept_guardrails` in place of `open`, `register_app` takes `identity`,
`transfer_app` takes `also` and `accept_guardrails`), and `app_status` and
`get_platform_status` answer in a new shape, so reconnect after that upgrade
too. Every skill learned the two properties: the identity question and the
two-app pattern for a public site at design time, the widening review and
the narrowing note, the contract's new R10 for anonymous apps with its
cookie rule, the uploaded-file rule, the front door's refusal, on a
members-only or internal app, of any request from another page that is not
a top-level GET navigation (so apps never
frame, include or call each other from the browser, and a data link is the
path between apps), the review of an app for every audience it can take,
and, for admins, allowing public apps, narrowing one in an emergency and
moving a linked pair together. The platform asks for at least
4.0.0 once the instance's admins raise `plugin.min_version`, as the v0.17.2
release asks.

## 4.1.0

Plugin 4.1.0 follows platform v0.17.3 and contract 36. No tool takes new
input, but `get_platform_status` no longer reports a membership authority,
so reconnect after that upgrade too. The skills follow what the release
changed: a purge takes a stopped app only, so an admin's fast takedown of a
public app is a stop, then a purge; a function app that still holds a
revoked data link's binding counts for `grant_access`, which refuses
`link_containment` until it is redeployed, and for `revoke_access`, which
rebuilds it; a locked backend credential has its own `connection_locked`
notice and email setting, and `connection_expired` means removed again;
app names may end in `-app`; the refusal codes renamed or added
(`link_containment` on `link_app_data`, `encryption_key_missing` and
`encryption_key_invalid`, `invalid_connection_name` and
`invalid_connection_definition`, `purge_app`'s `app_not_stopped` and
`r2_budget_exhausted`, `rebuild_app`'s `dispatch_in_flight`); numeric
settings refused outside their range; the retired `## Worker contract`
heading no longer passing the `CLAUDE.md` check; and the dependency gate
refusing a function app's `app/package.json` with no lockfile. The release
also corrected guidance that did harm when followed: the Dockerfile recipes
put comments after instructions, which breaks the build, so every comment
now sits on a line of its own; caching a backend credential is
`get_app_security` §8's rule, keyed so one person's credential never serves
another; and `inno-ship` gained rows for a superseded deploy
(`deployment_not_completable`, which must not be re-run blindly) and for
the deploy refusals it lacked. The platform asks for at least 4.1.0 once
the instance's admins raise `plugin.min_version`, as the v0.17.3 release
asks.

## 4.1.1

Plugin 4.1.1 follows platform v0.17.4, still contract 36. No tool takes new
input. A container app's release run now fails at its `container` job when
the upload that records the scanned image fails (`SBOM upload failed`, with
the platform's answer), and the platform refuses the deploy of a run that
recorded no image (`image_not_recorded`) before it mints or starts
anything; `inno-ship`'s rows tell an image too large for the platform from
an outage, and say where a stopped, mismatched or unlinked app's release
now fails. The first start of an app after a vulnerability finding uses no
self-service start, a start holds off the safety sweep for a while, and
`start_app`'s answer gives the time by which the fix must ship;
`inno-manage-app` relays it. A forced `transfer_app` rebuilds
function-shaped consumers only, since a container-shaped consumer's host
refuses the revoked link live. The v0.17.4 release does not raise the
floor: 4.1.0's rows misdiagnose a rare failure without breaking a build.

## 4.2.0

Plugin 4.2.0 follows platform v0.17.5 and contract 37. No tool takes new
input, but `app_status` and `get_platform_status` answer in a new shape, so
reconnect after that upgrade too. From this version the Version gate says
so itself. When its `get_platform_status` call fails with a validation or
schema error, it tells the user to reconnect the platform's server and
start the skill again (in Claude Code, `/mcp`, then Reconnect, or a new
session).

For members and owners, the skills follow what the release changed.
`app_status` lists the app's members, with the address a revoke takes. It
also names the revoked data links whose binding is still deployed, which
`list_app_links` lists too. When `revoke_access`'s cascade stops, its
warning names the redeploy, or an admin's `rebuild_app`, for each such
link. A `link_rebuild_pending` notice says that the code reading the
revoked source fails, and how to fix it. An instance whose manifest names a
support contact serves it on the status's `Support:` line. Each skill
that sends the user to a platform admin sends the request there, under
the rule `inno-manage-app` holds, and the platform's own refusals,
notices and sign-in pages name the contact too. The panel serves the
platform's user guide at `/guide`, for anyone signed in. A registered app
whose first deploy has not completed by the date `register_app`'s answer
gives is deleted, after a `first_deploy_due` reminder, and its name is
then free at once, unless another app still holds a deployed data link to
it.
`inno-new-app` and `inno-migrate-app` pass that date on at the hand-off,
and say that the members named at registration are told when the app
first deploys.

For admins, `list_apps` marks each running app's health and every
vulnerable app, and `get_platform_status` names the apps behind its
UNHEALTHY and VULNERABLE counts. The audit reference reads the release's
three new rows: `app_signin_denied`, `connection_connect_failed` and
`app_first_deploy_due`.

The v0.17.5 release does not raise the floor: its output changes are
additive, and what 4.1.x lacks is guidance, not a step that breaks.

## 4.3.0

Plugin 4.3.0 follows platform v0.17.6 and contract 38. No tool takes new
input and no tool's output moved, so there is nothing to reconnect for.
The skills follow what the release changed. `get_ci_status` names each
failed job's failed step and the last lines of its log, fenced as
untrusted data, so a skill can tell why a gate failed with no `gh`
installed, where it used to send the reader to the run link; a failing
gate now prints one titled line that says what failed and how to fix it.
A refused repository fails the `policy` job with `Platform refused this
app`, naming `app_mismatch` (with the app the repository is registered as
and the line to fix) or `repo_unlinked`, instead of running every gate on a
guessed policy, and a release tag on an unbuilt scaffold fails with
`Nothing deployed`. A deploy whose CI run fails releases its app at once,
so only a run that never reached its last step, or whose release warned
`App not released`, waits for the recovery sweep, and a restart of a
running app, or a start, checks the app's health again right after.
The secret scan reads every commit on every branch and tag, on every run, a
release tag's included, so a secret its default rules find anywhere in an
app's history fails its next release: `inno-ship`'s and
`inno-safety-preflight`'s gitleaks guidance gives the fix (rotate the
secret, then rewrite the history or record the finding's fingerprint in
`.gitleaksignore`, its only waiver), and never a new commit that deletes
the file.

The v0.17.6 release does not raise the floor, which stays 4.1.0: an older
build reads a failure from the run link and waits for the sweep where it
no longer has to, which costs time without breaking a step.

## 4.4.0

Plugin 4.4.0 follows platform v0.17.7, still contract 38. No tool takes new
input and no tool's output moved. A platform admin's MCP client now lists
the admin-only tools and a member's does not, and a client keeps the list
it read when it connected, so a person granted or revoked admin reconnects
to see the right one; `inno-fleet-admin` says when, and says which tools
are admin-only. The skills follow what else the release changed.
`get_app_contract` serves one requirement by its id (`sections: ["R3"]`),
so a skill that reads one requirement asks for that one alone, and
`["2"]` still serves all ten; a platform before v0.17.7 refuses an id with
`bad_request`, and the skills then ask for `["2"]`. A write tool's answer puts each caveat to act
on in a `WARNING:` line of its own and each note in a `NOTE:` line, where
`register_app` listed its caveats under `Warnings:` and `set_app_connection`
wrote `Warning:` and `Note:` (its sign-in and token sites on different
domains are now a `WARNING:`); the skills quote the new labels. The panel's
over-long note, reason or description is refused `text_too_long`, which
retires `note_too_long`. `register_app`'s second call may leave out `type`
and `description`, the first call's being used, and `inno-new-app` and
`inno-migrate-app` say so; `identity` still goes on both calls. The skills
name a `container` or `function` app a browser app, and a platform that
cannot ask the identity provider who holds an address one with no identity
provider lookup, as the platform's own text now does.

The v0.17.7 release does not raise the floor, which stays 4.1.0: 4.3.0
quotes labels the platform no longer writes and reads a whole section where
one requirement would do, which costs words without breaking a step.

## 4.5.0

Plugin 4.5.0 follows platform v0.17.9, still contract 38. No tool takes new
input and no tool's output moved. From v0.17.9 an app's address answers
from registration until its purge: until its first deploy starts it shows
a page saying the app has not been deployed yet (while that deploy runs, a
visitor meets the app's sign-in, where it has one, and then a page saying
the app is not available right now), and while the app is stopped a page
saying it is stopped and its owner can start it again. The
skills say what a visitor sees there: `inno-manage-app`'s `stop_app` and
`start_app` (a start serves the app again within seconds), `inno-new-app`'s
stop and its first-deploy URL, `inno-ship`'s first-deploy hand-over,
which tells the user to reload after a minute if they see the not-deployed
page, and its `container_rollout_failed` row, for an app none of whose
deploys has finished. `inno-ship` still never looks the address up itself:
the first deploy's switch from that page to the app leaves the name with no
DNS record for a few seconds, and a lookup then can be cached as missing
for minutes. `inno-fleet-admin` lists the admins' new `edge_mismatch`
notice: an app's custom domain out of step with its status, which the
hourly edge pass reports and never repairs, and the transition that brings
it back (for a never-deployed app, its first deploy, or, for an app nobody
will ship, `stop_app` then `purge_app`), with what each costs. Its
audit reference reads the edge pass's three rows, `app_edge_reconciled`,
`app_edge_mismatch` and `edges_reconciled`, and the `placeholder` key that
`app_created`, `app_stopped`, `app_started`, `deploy_completed` and
`app_purged` carry when they hold or release an address.

4.5.0 also corrects three sentences that platform v0.17.8, which released
no app plugin, made false. When `list_admins`' list is not simply what the
platform's admin table held, a line of its own under the list says where it
came from (the identity provider's admin group, or the manifest's
`identity.initialAdmins`), and `inno-fleet-admin` no longer quotes the old
words. A push builds and gates
a container app's image but generates no SBOM and records no image id,
which a release tag's run alone does; `inno-safety-preflight` and
`inno-containerize` say so.

The v0.17.9 release does not raise the floor, which stays 4.1.0: older
skills describe a stopped app's address as detached, quote `list_admins`'
old words and say a push builds the SBOM, none of which misleads a step a
build depends on.

## 5.0.0

Plugin 5.0.0 follows platform v0.17.11, still contract 38. Four tools take
new input, so reconnect after that upgrade too. The two variable tools
take lists under new names: `set_app_variables` takes
`variables: [{ name, value, secret? }]` and sets them in one call, so a
container app starts one new container instance for all of them, and
`remove_app_variables` takes `names`; each refuses a call with one bad
item whole, naming the item when the call names two or more, and stores or
removes nothing. `mark_all_notifications_read` takes `scope`: `mine`, the
default, marks the caller's own notices (an admin's include the admins'
shared ones), and `platform`, a platform admin's alone, marks every notice
on the platform. The admin-list import takes `apply` alone. The skills
follow, and say what platform v0.17.10 changed: a start of an app that
never completed a deploy returns it to not deployed with its first-deploy
window started again and uses no self-service start; an answer a retry
will not help says whom to tell; a support bundle goes to a platform
admin; a connect page answers a backend's redirect with
`<backend> refused the connection`; and `inno-ship` reads the `Trivy`,
`Docker build` and `Dependency install` failure titles. The v0.17.11
release raises the floor to 5.0.0, so the platform tells every 4.x build
to update, and its skills stop at their Version gate until it does.

## 5.1.0

Plugin 5.1.0 follows platform v0.17.12, still contract 38, with no tool's
input or output changed, so no reconnect is needed. The
`link_rebuild_pending` notice is now `link_revoked`, its email setting
`notify.email.link_revoked`; notices sent before keep the old stage, which
`inno-manage-app` says. The skills say what `host_check_failed` asks
of an owner (a retry when the read failed, a platform admin when the token
lacks access), that a release restarts a container only when it moves the
host build, and point at one home for a never-deployed app's start and a
registration's deadline. `inno-ship`'s bundle rows read the bundle's
annotation, which now separates the code and the message with "; " as the
token's and finalize's do, and a local `deploy-bundle` refusal starting
"deploy-bundle failed: ". The floor stays 5.0.0.

## 5.1.1

Plugin 5.1.1 is a fix within `inno-containerize`, still against platform
v0.17.12 and contract 38, with no tool's input or output changed. The local
sanity check in `references/local-check.md` now owns what it creates: each run
builds its own image tag and names its containers after it, removes only those
(after a Ctrl-C too) and never a container some other run or tool named,
publishes the smoke container on a free loopback port instead of the host's
8080, so another local service cannot pass the check for it, and stops with a
`FAIL:` line when the build fails or the smoke container cannot be created or
started, rather than checking a stale image. An app that crashes on boot still
reports that it exited, with its logs. The non-root user check decides exactly
as before. The floor stays 5.0.0.

## 5.1.2

Plugin 5.1.2 follows platform v0.17.20 and contract 39, with no tool's input
or output changed, so no reconnect is needed. Its fixes are wording within
the existing workflows. `inno-add-connection` names the new
`app_type_unsupported` refusal (an identity-aware app of any type but
`mcp-container` takes no Connection, and one left on it can still be listed
and removed), and the check order for the connect page's "Not available"
counts that cause and starts with `app_status`. `inno-new-app` and
`inno-migrate-app` say that `register_app` echoes `connections` as a
reminder only for such an app, answering any other type that it takes none.
A `client_auth: "basic"` pair holding characters beyond ASCII letters,
digits and `*-._` can be refused `invalid_client`, with `"post"` the remedy,
and a "Connecting failed" 502 that repeats points at the backend's token
endpoint. The health re-check after a deploy, start or restart is said to
run only when `health.probe_enabled` is on for the app.
`inno-safety-preflight` names a crashed accessibility scanner, and the MCP
client's "No access" page's next step, restarting the app's connection, is
in `inno-manage-app`. The floor stays 5.0.0.

## 5.1.3

Plugin 5.1.3 follows platform v0.17.21, whose Connect Claude Code card offers
the plugin alone: this README no longer lists a bare `mcp add` among the
card's commands. No skill or tool changed; the floor stays 5.0.0.

## 5.2.0

Plugin 5.2.0 follows platform v0.17.22. When the user means a new app for
everyone who signs in or for the public, `inno-new-app` now reads
`access.allow_internal` or `access.allow_public` for the user during design
(`get_config user=`) and says up front whether a platform admin has to allow
it, instead of the user learning so at the widening review after the app is
built. `inno-ship` gives the steps to add a shipped MCP app as a connector in
Claude Desktop or claude.ai, and in Claude Code, and this README says how to
add the platform itself to Desktop or claude.ai. The floor stays 5.0.0.

## 6.0.0

Plugin 6.0.0 follows platform v0.17.23, still contract 39. That release
signs people in through any OpenID Connect identity provider and keeps Okta as
the one directory it can read accounts from. The platform no longer serves
the admin group's marking tool (claim_instance_objects), so it lists 53
tools, and the admin-list import is now `import_admin_group`
(import_okta_memberships before), whose `counts.okta_failed` is
`counts.directory_failed`; `grant_admin`'s `okta_user_not_found` is
`directory_account_not_found`, and `list_admins`' `okta_fallback` source is
`directory_fallback`. `get_platform_status` gains an `Identity provider:`
line, and an `identity` object in its typed output, naming the provider by
the instance's display name and saying whether the instance has a
directory; with none, the line says what the platform cannot learn and
which settings shorten it. The skills follow: `inno-fleet-admin` names
`import_admin_group` and `directory_account_not_found`, drops the marking
tool's section, says what an instance with no directory does at each step
(the import refuses `directory_unavailable`, an offboarding relies on
`revoke_sessions` and `revoke_access`, and a purge deletes nothing at the
identity provider), and every skill names the identity provider where it
named Okta. The v0.17.23 release raises the floor to
6.0.0, so the platform tells every 5.x build to update, and its skills stop
at their Version gate until it does: update and reconnect once, as at
5.0.0.

## 6.0.1

Plugin 6.0.1 follows platform v0.17.23, still contract 39. `inno-new-app`
names every file each type's scaffold ships (a `function` repo has no
`app/package.json` until a dependency is added) and has the agent list the
repo's files before reading them, so reading the reference code no longer
names a file that is not there and shows the user a "Failed" step. No tool
changed; the floor stays 6.0.0.

## 6.1.0

Plugin 6.1.0 follows platform v0.17.24, contract 40. The platform's own
answers and its contract documents now say "directory" for the identity
provider's account lookup, as the skills already did, so `inno-fleet-admin`
drops the note that bridged the two words. Sign-in now follows the
provider's discovery document for how the platform authenticates at its token
endpoint, and a directory named without its secret shows a red dot on the
panel's Status card. No tool changed; the floor stays 6.0.0.

## 6.2.0

Plugin 6.2.0 adds `inno-convert-artifact`, which turns a Claude artifact
(React or HTML) into a function app whose browser interface the platform's
CI builds from `app/ui/` (a build inno-platform's pull request 67 added:
upstream's mirror has published it since 2026-10-31, and an instance's own
mirror takes it with platform v0.18.1, where contract version 42 names it in
§1.1, Browser interface). The skill gets the artifact's source, inventories what claude.ai
provided (libraries, `window.storage`, `window.claude`), plans and gets
approval, registers through `inno-new-app`'s steps, then builds the app from
a starter: a Worker serving the page and hashed assets under a strict
Content-Security-Policy, `/api/me` for the sign-out bar, and `/api/storage`,
a D1-backed `window.storage` with personal and shared scopes, same-origin
POST only, bounded keys and values. Local runs use `app/dev/` (CI's build
shape, and a proxy that adds stand-in identity headers). `window.claude` is
not supported. `inno-new-app` and `inno-migrate-app` point an artifact to
it, and the README counts ten skills.

## 7.0.0

Plugin 7.0.0 follows platform v0.18.0, contract 41, which learns who may
sign in from the identity provider over SCIM 2.0 and retires the directory.
The platform setting `auth.provisioning` is the membership mode: `jit`, the
default, where anyone the identity provider lets sign in is a member, or
`scim`, where only an active account the provider pushed may sign in, beside
every `identity.initialAdmins` address, the break-glass. In scim mode a
deactivation ends the person's sessions and moves the apps they own into the
custody of the first `identity.initialAdmins` address, and they return when
the account is active again. The platform lists 55 tools:
`create_scim_token`, `revoke_scim_token` and `get_provisioning` are new and
admin-only, and the admin-list import, `import_admin_group`, is gone, since
`identity.initialAdmins` seeds an empty admin list on every instance.
`set_config` takes `confirm`, the blocked count that the preview of a switch
to scim reported (its refusals are `preview_required`, `preview_stale`,
`initial_admins_required` and `no_pushes_yet`); `query_audit`'s `surface`
takes `scim`; `grant_admin` looks nobody up, so `directory_account_not_found`
is gone; and `get_platform_status`' `identity` output names the mode, the
pushed account counts and the last push in place of the directory, so
reconnect after that upgrade. `inno-fleet-admin` follows with the mode, the
tokens (a new one best made on the panel's Identity tab, which keeps it out
of the conversation), the previewed switch, custody and the break-glass, and
drops the import; `inno-manage-app` says what a deactivation does to a
person's access and to the apps they own in each mode; and its grant
warning, like `inno-new-app`'s, comes only where the platform checks
addresses. The v0.18.0 release raises the floor to 7.0.0, so the platform
tells every 6.x build to update, and its skills stop at their Version gate
until it does.

## 7.0.1

Plugin 7.0.1 follows platform v0.18.1, contract 42. Custody follows
`identity.initialAdmins`: the hourly pass hands any held app to the first
address, which keeps the mark, so a change to the list strands nothing, and a
held app goes back to its person when their account can sign in again. The
custodian's member row lasts exactly as long as custody. `revoke_access`
refuses the person an app in custody is held for, with
`owner_not_revocable`, as it refuses an owner. The switch to scim counts app
owners who never signed in (`blocked_never_signed_in`), blocks people under a
budget of 600 statements and leaves the rest to their next status check and
the next hourly pass. `inno-fleet-admin` and `inno-manage-app` say so. No
tool changed; the floor stays 7.0.0.

## 7.0.2

Plugin 7.0.2 follows platform v0.18.2, contract 42. A login the identity
provider reuses gets a fresh account, and the earlier holder's apps stay in
custody; a person assigned again is matched by `externalId`. The switch's
count (`blocked_never_signed_in`) now covers owners whose address has passed
to someone else, and a push's block and the switch leave the address's panel sessions
alone. A provisioning app that sends its token as the whole header takes
`Bearer <token>`, and its group import stays off. `inno-fleet-admin` says so.
No tool changed; the floor stays 7.0.0.

## 7.0.3

Plugin 7.0.3 follows platform v0.18.3, contract 43. `inno-convert-artifact`
deletes `app/.needs-build` once the artifact is in, so its preflight runs the
interface build. `inno-manage-app` no longer mentions the status's `Admin
group:` line, which the platform stopped serving, and the connect page's
"Account inactive" is worded for the mode (scim mode refuses an inactive,
deleted or never-pushed account; jit mode refuses none for status). No tool
changed; the floor stays 7.0.0.

## 7.1.0

Plugin 7.1.0 follows platform v0.18.4, contract 43. Custody is visible to the
reads: `app_status` has a `Custody:` line and a `custody` field, `list_apps`
marks `[IN CUSTODY]`, and a transfer of a held app says it ended custody
(`inno-fleet-admin` reads `app_status` first, and its audit and custody
references name `custody_kind`, `custody_ended_for`, `custody_move_failed`,
the custody pass's `access_enforcement_stalled`, `keys_deleted` and the
switch's `apps_moved_count`). The connect pages' "Account inactive" is now the
"Sign-in refused" page (HTTP 403), and Start fresh removes the connections of
the account signed in, never another account's at the address. No tool
changed; the floor stays 7.0.0.

## 7.2.0

Plugin 7.2.0 follows platform v0.18.5, contract 44. A backend's permanent
refusal of the app's own client now answers `502 connections_upstream_refused`
(`inno-add-connection` and `inno-platform-conventions` say to tell the user
the owner has been told, and not to retry), and the owner gets a
`connection_refused` notice (`inno-manage-app`). `scripts/check-build-tools.sh`
checks the starter's build tool pins against the pinned record. No tool
changed; the floor stays 7.0.0.

## 7.2.1

Plugin 7.2.1 follows platform v0.18.7. The receiver now stores and lists the
groups an identity provider pushes (`get_provisioning`'s `groups` count and
the Identity tab); a group grants nothing yet. `inno-fleet-admin` says what to
turn on in Okta and Microsoft Entra ID, to leave Okta's Import Groups off, and
that `/Bulk` and `/Me` still answer 501. No tool changed; the floor stays
7.0.0.

## 7.3.0

Plugin 7.3.0 follows platform v0.18.8 and contract 45. A group the identity
provider pushes, named `<groupPrefix><app>-users`, now admits its members to
that app beside its member list, in either membership mode, and never makes
an admin: admin standing stays the platform's own list, and the manifest key
`naming.adminGroup` is retired. `inno-manage-app` says that `revoke_access`
removes only a member row and answers when a group still admits the person
(changed only at the identity provider), that `grant_access` to a group
member adds a second way in, and that `app_status` shows each member's way
in (`way_in`, the `Group:` line). `inno-fleet-admin` says how to push the
groups, to keep group prefixes distinct across instances sharing an identity
provider, and that the SCIM token can admit a person to an app through its
group but can never make an admin. No tool was added or removed: the
descriptions of `app_status` and `revoke_access` moved, and `app_status`'
output gained `way_in` on each member. The floor stays 7.0.0.

## 7.3.1

Plugin 7.3.1 follows platform v0.18.9 and contract 46. A group request to the
SCIM receiver may now be 1 MiB (about 23,300 members at once, where 64 KiB held
about 1,400), a listed page of groups with their members carries at most about
10,000 members, and the conflict notice (`member_reassigned`) and its audit row
(`identity_conflict`, `still_member_through_group`) name a group that still
admits the new account. `inno-fleet-admin` and `inno-manage-app` say so. No
tool changed; the floor stays 7.0.0.

## 7.3.2

Plugin 7.3.2 follows platform v0.18.10 and contract 46. `inno-new-app` and
`inno-ship` now say a members-only app admits its identity provider group too,
beside its member list, as `inno-manage-app` already did, and `inno-new-app`'s
two-app pattern says an editor's members may reach a members-only site through
its group. `inno-platform-conventions` no longer names a platform admin group
among what `X-Forwarded-Groups` never carries. No tool changed in behavior
(three tool descriptions are reworded); the floor stays 7.0.0.

## 7.3.3

Plugin 7.3.3 follows platform v0.18.11 and contract 47. `inno-add-connection`
now reads a header-delivery credential's `header` as well as `access_token`,
leaves `refresh` at its default, prefers the default `client_auth`, and says
what the "Start this connection again" page and the `401 unauthorized` and
`400 bad_request` seam answers mean. `inno-ship` and `inno-safety-preflight`
route a scanner's own fault apart from a finding and name the
`deploy_denied:workflow` refusal as the author's to fix; `inno-ship` also gains
rows for the browser interface build, a `deploy-token` timeout and a failed
image push;
`inno-containerize` gains two probe-clock clauses. `inno-manage-app` and
`inno-fleet-admin` point at the one-click redeploy of a recent release from the
panel and say that a suspended person keeps their stored credentials while a
deleted one loses them; `inno-manage-app` also says how long a deactivation
takes to reach an app, that a variable change re-checks a running container
app's health, what a `member_reassigned` notice says on an internal or public
app, and that the platform's own MCP sign-in can show the "Sign-in refused"
page. `inno-ship` routes a function app's `diagnostics_unavailable` (a
platform with no diagnostics storage) to a platform admin, with no re-run and
no support bundle, and `inno-platform-conventions` counts a group change's
window from the identity provider's push. On the platform's side, six tool
descriptions and three answers are reworded (the jit sentence, the narrowing
to members-only, and `grant_admin`'s re-grant over a pinned row),
`list_connections`' fleet view and `list_user_connections` now answer at most
100 and say when more exist, a variable change on a running container app
re-checks its health, as a restart does, `request_start`'s email to the
admins obeys the instance's lifecycle email switch, a data link's containment
judges a pinned person by the address they sign in with now (so `grant_access`,
`transfer_app` or `link_app_data` can be refused `link_containment` where it
passed before, or the reverse), and a health probe answered 401, 403 or 302
names the app's own `/healthz` answer as a cause; the floor stays 7.0.0.

## 7.3.4

Plugin 7.3.4 follows platform v0.18.12 and contract 47. It fixes
`inno-convert-artifact`'s starter, which the plugin's repository now runs and
tests in CI. In `app/storage.ts`: a failed first create of the storage table
no longer fails every later storage call on the same Worker instance, and a
database fault answers `503 storage_unavailable` instead of an unhandled
error; a value may be 1,900,000 bytes of UTF-8 (it was 1,000,000 characters,
which a large value outside ASCII could pass only for production D1 to refuse
it), and the starter's exported `MAX_VALUE` is now `MAX_VALUE_BYTES`, counting
bytes, for any converter whose own code read it; a request's body is bounded
at 4,000,000 bytes, twice the value limit so that JSON's two-byte escapes (a
quote or a backslash) never push a value at its limit over (`413
body_too_large`), though a value full of raw control characters still can, a body that is not a JSON
object answers `400 bad_request`, and a list prefix over 200 characters or not
a string answers `400 bad_prefix` instead of listing every key; a call is
checked whole before any statement runs; the 1,000-key quota is checked inside
the write, so concurrent new keys can no longer overshoot it; and a list
prefix holding an emoji finds its keys. In `app/dev/serve.mjs`, `npm run dev`
now answers this machine only, and on both its ports (the proxy's 8787 and
wrangler dev's 8788) only to the names `localhost:8787` and `127.0.0.1:8787`,
so a web page that points its own name at this machine is refused. The skill's
HTML conversion also moves literal `style="..."` attributes into classes,
since the page's policy drops them. Anyone who converted an artifact on plugin
6.2.0 to 7.3.3 should copy the new `app/storage.ts` and `app/dev/serve.mjs`
from the starter into their repository: the table and its schema are
unchanged, so saved data carries over. No platform tool changed in v0.18.12;
the floor stays 7.0.0.

## 7.4.0

Plugin 7.4.0 follows platform v0.18.14 and contract 47 (no platform tool
changed in v0.18.13 or v0.18.14; the floor stays 7.0.0). It reshapes the
skills and the starter. `inno-manage-app` and `inno-fleet-admin` open on a
**Find the task** table, one row per task their descriptions name, and their
long procedures moved into references that each heading points at
(manage-app's `references/sharing.md`, `audience.md`, `variables.md`,
`notifications.md` and `deactivation.md`; fleet-admin's
`references/admin-standing.md`, `scim.md`, `transfer.md`, `offboarding.md`
and `admin-notifications.md`), each heading naming the stops its reference
holds, so a task loads 23.5 to 44 percent less text.
`inno-safety-preflight/references/gate-failures.md` holds each safety gate's
cause and fix once, for a push and a tag alike. Every skill's description
quotes its trigger phrases, the six workflow skills number their steps and
end on a hand-off naming the next skill, `inno-new-app`'s intake asks seven
questions and states the type, pattern and stack as recommendations,
`inno-migrate-app` registers by `inno-new-app` §3 and keeps only what a
migration changes, and the Version gate every skill opens with is written
from one source (`scripts/version-gate.md`) and checked in CI. The
per-release history moved from the README to this file. In
`inno-convert-artifact`'s starter, `npm run dev` (`app/dev/serve.mjs`, with
the new `app/dev/wrangler-config.mjs` it reads) now serves only its own
Worker and lives as long as it does: wrangler dev runs on a free port of its
own (or `DEV_WORKER_PORT`) in a process group of its own, the proxy forwards
nothing until that port answers with a token made for the run, startup fails
when the Worker cannot start or another process holds its port, the proxy
closes when wrangler dev exits, and Ctrl-C stops everything; `DEV_PORT` moves
the proxy from 8787, so two apps can run at once. `app/ui/storage-shim.ts`
gives every request a 30-second deadline, never sends one again by itself,
and fails with a `RequestError` whose kind (`signed_out`, `refused`,
`unavailable`, `timeout` or `network`) and message a page can show, marking a
write whose answer was lost as possibly stored; an artifact's own
`window.storage` calls keep working and still reject with an `Error` naming
the app's reason. `app/ui/AppBar.tsx` puts "Signed in as" before the address
for screen readers, shows a failed read with Try again, and offers to sign in
again once the session has ended; the placeholder `app/ui/Artifact.tsx` shows
the loading, failed-read, saving and failed-save states; `app/storage.ts` and
`app/index.ts` declare `Env` once, with no change in behavior. The skill's
dev-server, app-bar and storage-error guidance follows the new starter, and
`references/html-artifacts.md`'s step 7 now has an HTML conversion's own
`app/ui/app-bar.ts` do what `AppBar.tsx` does.
Anyone who converted an artifact on plugin 6.2.0 to 7.3.4 should copy
`app/dev/serve.mjs` with `app/dev/wrangler-config.mjs` and
`app/ui/storage-shim.ts` from the starter into their repository, and then,
for a React conversion, copy `app/ui/AppBar.tsx` too (and replace
`APP_TITLE` in it again), or, for an HTML conversion, which has its own
`app/ui/app-bar.ts` in place of that file, bring the bar up to
`references/html-artifacts.md`'s step 7 (the signed-in address through the
shim's `send()`, the failed read with Try again, and Sign in again at
`signInAddress()`); saved data is unchanged.

## 7.4.1

Plugin 7.4.1 follows platform v0.18.16 and contract 47 (no platform tool
changed in v0.18.15 or v0.18.16; the floor stays 7.0.0). Platform v0.18.16
gives every job of the tenant workflow a name, and a run page,
`get_ci_status` and `gh run view` now show each job by that name, after
`deploy.yml`'s own job (`platform / Config integrity`), where they showed its
id: `policy` (shown as Gate policy), `config-integrity` (shown as Config
integrity), `secrets` (shown as Secret scan (gitleaks)), `sast` (shown as
SAST (semgrep)), `deps` (shown as Dependency audit), `container` (shown as
Container contract and image scan), `dep-age` (shown as Dependency
cooldown), `scaffold-check` (shown as Scaffold check), `app-build` (shown as
Build the app Worker, its name before too) and `deploy` (shown as Deploy).
The ids are unchanged, but the skills, their references and the README named
a job by its id where a person reads the run page. Each row of a failure table
now gives the name beside the id, in that form, once for every job the row
reads on a run (failing, passing, running or skipped), and so does every list
of a run's jobs and every other paragraph or list item about a job failing or
what a run shows of it; the ids left alone are in sentences about what a gate
checks or what a job needs or does, pointers to a table row, gate toggle names
and later mentions in the same row or passage.
`inno-safety-preflight` §2 matches a failure row by the failed job's name as
`get_ci_status` and `gh run view` print it, and §2 and
`references/gate-failures.md` both say that a platform before v0.18.16 shows
every job but `app-build` by its id. `inno-containerize` now says a failed
smoke test skips `deploy`, as the run page shows, where it said it fails it.
No starter file changed.

## 7.4.2

Plugin 7.4.2 follows platform v0.18.17 and contract 47 (no platform tool
changed in v0.18.17; the floor stays 7.0.0). Platform v0.18.17 gives every
refusal a deploy route answers a `message` saying what to fix, except the
authentication refusals, which stay bare: `deploy_denied` and its
`deploy_denied:<reason>` codes, `oidc_invalid` and the broker's other
`*_denied` codes. CI prints each as `<call> failed (<status>): <code>:
<message>` (`deploy-token failed (409): app_not_ready: ...`), where it
printed some as the bare `{"error":"<code>"}`. `inno-ship`'s
`references/deploy-failures.md` quoted two of those, and now says what the
platform prints. Its `app_not_ready` row quotes the line the run now shows,
which names the provisioning to finish. Its `deployment_not_completable` row
told two cases apart from the others by their having no message: a
deployment that is not one of the app's, and one that stopped being in
progress while the finalize attached its host, whose host may already serve
the release. Each now has a sentence of its own, and the row tells all four
cases apart by their message, each with the fix it had. `inno-ship` §3
points at the second of those by its message, where it named the case
message-less. Both rows say what a platform before v0.18.17 answers. The
`deploy_denied:workflow` row, whose line says the platform gave no reason,
and the other refusals that give none are unchanged. Platform v0.18.17 also
leaves `text_too_long` with no writer: the panel refuses an over-long note
`bad_request`, and over MCP the argument's own limit refuses it first, as
before. `inno-manage-app`'s list of `set_config` refusals drops the code and
says that, over MCP, an over-long note is refused by its argument's limit
(200 characters) before the tool runs: shorten it and call again. No starter
file changed.

## 8.0.0

Plugin 8.0.0 follows platform v0.18.18 and contract 47. That release renames
tool arguments, so this is a major: a person's address is `email` on every
tool that takes one by address, where `transfer_app` took `new_owner_email`
and `list_user_connections`, `disconnect_user_connection` and `get_config`
took `user` (`set_config`'s and `remove_config`'s `scope_id` stays, since it
names an app or an address). `restart_app` answers a `function` or
`mcp-function` app `app_type_unsupported`, its message naming the app's
type, where it answered `not_a_container`. `get_platform_docs` serves its
document in 20 numbered sections and takes an optional `sections` argument
with `get_app_contract`'s grammar, and the tools' descriptions name the
section they mean ("get_platform_docs section 16"). The skills follow:
`inno-fleet-admin`'s `transfer_app` heading takes `email`; `inno-manage-app`,
`inno-fleet-admin` and `inno-new-app` read an account's settings with
`get_config email=<address>`; `inno-manage-app`'s restart paragraph names
`app_type_unsupported`; and every pointer into the platform's docs, the
README's included, names its section by number with its title, such as
`get_platform_docs` section 11 (Lifecycle), where it named the section's
bold title. Every listing line now takes one grammar: a head (`- `, what
the line names, then its bracketed tags) and then `key=value` pairs, so
`inno-fleet-admin` and `inno-manage-app` read `list_apps`' line as
`- <name> [<status>]`, its marks (`[IN CUSTODY]` first, then
`[VULNERABLE]` and `[UNLINKED]`, beside the status where they came last),
then `type=`, `audience=`, `identity=`, `owner=`, `url=`, `repo=`
(`(pending)` while registration has recorded none) and `health=`, and
`query_audit`'s rows as pairs whose `actor=` and `detail=` values arrive
fenced in «» (`list_connections`' line, which the grammar follows, is
unchanged). The platform's tools now print ASCII arrows only, so
`inno-new-app` quotes `register_app`'s first line as `Registration started
for "{name}" <- {repo}.`, where it quoted the Unicode arrow (U+2190); and
a counted noun in a tool's answer now agrees with its count (`1 line`,
`2 lines`), where some read `line(s)`, which no skill quoted. The
v0.18.18 release raises the floor to 8.0.0, so once the instance's admins
raise `plugin.min_version` to it, the platform tells every 7.x build to
update, and its skills stop at their Version gate until it does. The
platform keeps no alias for the old names, and until that gate is set a
7.x build's calls that use them are not all refused: `transfer_app` and
`disconnect_user_connection` refuse a call that omits `email`, while
`get_config` and `list_user_connections` ignore the old `user` key and
answer as if no address were named, within the caller's standing (an
admin's `get_config` answers the fleet catalog and `list_user_connections`
the fleet's sessions, where one account's was asked for, and a member's
either one answers `forbidden`), so update before reading one account's
settings or sessions. The tools' input
changed, so reconnect after that upgrade too. `inno-convert-artifact`'s
starter `app/dev/build-ui.mjs` gains a header naming the platform's
`ci/build-ui.mjs` it mirrors (at v0.18.18, last changed in ac8c1f4f, with
its sha256) and what a local build does differently: an app converted on
an earlier release may copy it again for that header, and its code is
unchanged, so it builds as before either way. This repository now checks
that header against the platform's record and builds one corpus with both
builders to compare what they write.

## 8.0.1

Plugin 8.0.1 follows platform v0.18.20, which names every hourly pass's
audit rows by the pass's label and rewrites the stored history to match
(migration 0076). `inno-fleet-admin`'s audit rows reference names both
eras, since its floor, 8.0.0, still serves an instance before v0.18.20: the
containment pass audits as `containment` (`containment-pass` before it),
the edge pass as `edges` (`edge-reconcile` before it), and the lifecycle
run's `app_first_deploy_due` row as `lifecycle` (`scheduler` before it). On
an instance at v0.18.20 or later, filter `query_audit` by the new names,
since 0076 rewrote the stored rows to them. No tool's schema changed;
`query_audit`'s `actor` description now gives `lifecycle` as its example,
which a client shows after it reconnects. The floor stays 8.0.0.

## 8.0.2

Plugin 8.0.2 follows platform v0.18.21, which words its own pages one way:
no contraction, no "please", and no link called invalid. The
`inno-add-connection` skill's connect page reference quotes two of those
pages, so it now reads "Your encryption key is not reachable from here",
where it read "isn't", and "Connection link not valid", where it read
"Invalid connection link". No tool changed, so there is nothing to
reconnect, and the floor stays 8.0.0.

## 8.0.3

Plugin 8.0.3 follows platform v0.18.26, in which a move of an app's
ownership reaches its deploys, and a stop wins over a deploy in flight.
Every move of ownership (a transfer, one to the owner's own address
included, a move into custody, a hand-over and a return) holds the app's
deploys, since its repository does not change hands and still holds its
code: CI's policy step and every deploy step refuse new code with
`deploys_held` until the app's owner, once their owner row is pinned to
their account, keeps the bound repository (`register_app` with the app's
name and that repository) or moves the app to another they control
(`register_app` with another repository, in a registration's two calls),
and only a rebuild of the commit the app serves deploys meanwhile. An app
in custody, or one whose owner can no longer sign in, is refused the same
way (`app_in_custody`, `owner_inactive`). A stop of a deploying app ends
that deploy and stops the app, so `purge_app` answers a deploying app
`app_not_stopped`, only `restart_app` and the two variable tools still
answer `app_deploying`, and the recovery sweep counts its two run
intervals from when the app entered deploying. `inno-manage-app` gains a
**Held deploys: keep or move the repository** section and a Find the task
row for it, with the keep, the move, each answer that leaves the hold in
place, and the rule that whoever can push a release tag to the kept
repository controls the app's code. `inno-ship`'s `references/deploy-failures.md`
gains a row for the three refusals, and `inno-safety-preflight` sends a
`deploys_held` refusal to the owner rather than to an admin.
`inno-fleet-admin` gains a Find the task row, a **Held deploys** paragraph
in its transfer reference, what custody and offboarding now refuse, the
re-point's ending of the moved-from account's sessions and MCP grants,
and the new audit rows (`deploys_resumed`, `repo_rebound`, the three
`deploy_denied` reasons, `app_stopped`'s `ended_deployment` and
`app_deploy_recovered`'s `via: "stop"`). `inno-new-app` and
`inno-migrate-app` read the move's answers, and every skill that said a
stop waits for a deploy, or that a transfer needs nothing redone, now says
which platform release each behavior belongs to, since 8.0.x still serves
earlier ones. No tool's schema changed, so there is nothing to reconnect,
and the floor stays 8.0.0.
