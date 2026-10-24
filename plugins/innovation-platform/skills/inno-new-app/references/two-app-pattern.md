# The two-app pattern: a public site with an editing area

Read this when the user wants a public site with an editing area, wants to
collect submissions from the public, or wants an existing app made public:
from `inno-new-app` §1b, from `inno-migrate-app`, or from `inno-manage-app`
when `set_app_access` answers `audience_needs_anonymous`. Only an anonymous
app can be public, and an app's identity never changes, so each of those is
two apps joined by a data link.

## The two roles

- **The site, an anonymous app.** It owns what is published and anything
  visitors submit, in its own database and files. It renders only what is
  meant for anyone, and stores submissions without ever showing them (the
  contract's R10, `get_app_contract` with `sections: ["R10"]`). It is the app
  that is widened to public.
- **The editor, an identity-aware app**, members-only by default, linked to
  the site as its consumer (`link_app_data` with the editor as `consumer`
  and the site as `source`). Through the link it writes what is published,
  uploads files and reads submissions. The link is read-write over the
  site's database and every one of its files, and on a public site a write
  is published at once (`link_app_data`'s description, and contract §2.1,
  `get_app_contract` with `sections: ["2.1"]`). An editor widened to
  internal must gate its submission views on `member` (the identity
  helper's test), since everyone who signs in reaches it.

A link never widens who reaches the source's data (contract §2.1's nested
containment): a consumer may read a source only when everyone who reaches
the consumer reaches the source. Everyone reaches a public site, so any
editor may read it; while the site is still members-only, every member of
the editor must be on the site's list.

## The order, by case

**A new pair.**

1. Register the anonymous site and a members-only editor: `inno-new-app`
   twice, with `identity: "anonymous"` for the site and identity-aware for
   the editor.
2. Grant the editor's members on the site (`grant_access`), so the link
   below is contained. That is fine for an anonymous source, whose content
   is meant for anyone, and the guardrails' **Data handling** section says
   so in one sentence of its cross-app data links bullet (`get_guardrails`),
   so that bullet's rule against widening a source's membership to satisfy
   the check is not read against it.
3. Link: `link_app_data` with the editor as `consumer` and the site as
   `source`, then deploy the editor (a link takes effect on the consumer's
   next deploy).
4. Preview the site with real content, written through the editor.
5. Run `inno-manage-app`'s widening review for the site, then widen it to
   public with `set_app_access`.

**An existing app becomes the editor.** It keeps its address, its users and
its private data, and a new anonymous app at a new address becomes the
site.

- If it is members-only, follow the new pair's order from step 2 (grant its
  members on the site).
- If it is internal (everyone who signs in reaches it), it cannot read a
  members-only site, but it may read an internal one (contract §2.1's nested
  containment), so the site goes internal first: register the site, ship
  it, run `inno-manage-app`'s widening review for internal and widen it,
  then link the editor to it and deploy the editor. Preview the site with
  real content written through the editor, as everyone who signs in can,
  and only then run the review for public and widen it.

**Making an existing app public** is the same recipe: the existing app
becomes the editor, and nothing it ever stored is public unless the owner
copies it to the site. Say so before starting, and say that the public site
has a new address while the existing app keeps its own, with its users.

## Files someone uploaded

Whichever app serves a file someone uploaded serves it only as a download,
with `Content-Disposition: attachment`, `X-Content-Type-Options: nosniff`
and `Content-Security-Policy: sandbox`, never inline, from any host on the
platform. That covers a visitor's upload the editor republishes on the site
and a file the editor reads from the site through the link. The rule's home
is `get_app_security` §3; `inno-platform-conventions`' **Files someone
uploaded** has the plugin's summary and the template's helper that returns
the three headers.

## Two slots, one transfer

- The pattern spends two of the owner's active-app slots
  (`apps.max_active`): check the limit with `check_name` before registering
  the second app (`inno-new-app` §1).
- The pair moves together: a platform admin's `transfer_app` names one app
  of the pair as `app` and the other in `also`, which keeps the link between
  them, and a public site's transfer needs the admin's
  `accept_guardrails: true` after the review (`inno-fleet-admin`). An owner
  asks an admin (`inno-manage-app`'s **Transferring an app: ask an admin**).
