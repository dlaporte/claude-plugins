# When a member's address passes to another person

Read this when a result or a notification says an address now belongs to a
different account than the one its grant is pinned to (`grant_access` on
someone the member list already holds, a `link_containment` refusal or a
grant on a linked source app, a narrowing of a source app, or a
`member_reassigned` notification), when a grant's result says the row is
pinned and the platform (with no directory to read accounts from, as the
`Identity provider:` line of `get_platform_status` says) cannot ask
whether the address has passed to someone else, or when a result names
another address to revoke or the address a person's row is stored under. A
grant is pinned to the identity provider account that holds its address;
`grant_access`'s description says how, and where a sign-in is matched by its
address instead.

The grant stays with the account it is pinned to, and every sign-in carries
the person's identity provider subject (the panel's, an MCP client's, and a
browser app's, which is the platform's own), so the address's new holder is
refused like anyone the app does not admit (contract R3, `get_app_contract`
with `sections: ["R3"]`).

**Sharing with the new holder.** Confirm with the owner first: the revoke
also ends the access of the account the row was pinned to, which may be the
same colleague under a new address; if they should keep it, grant that new
address too. Then run `revoke_access` and then `grant_access` for the
address. The new grant is pinned to whoever holds the address now.

**The owner's own address.** Only a platform admin moves the app to the
address's new holder: `transfer_app` to that same address, or, on a platform
with no directory, the hand-off through another address that
`grant_access`'s answer names. Offer to draft the request, as the skill's
**Transferring an app: ask an admin** says.

**A linked source app.** A link, a grant and a narrowing compare people,
not addresses, so a source app that lists the address for the account that
held it before can refuse a grant here with `link_containment`, and a
narrowing of this app names a consumer's member it lists for another
account. The fix is
the same re-share on the app that lists the old account (`revoke_access`,
then `grant_access`), or, when that address is that app's owner's own row, a
platform admin's `transfer_app` of that app to it.

**One person, one row.** A grant to an address whose account the member
list already holds under another address writes nothing, and the result
names the address that row is stored under: that is the address to revoke.
A revoke acts on one row: when the account is still a member through
another row, the result names the address to revoke next. Revoke that one
too if the person should be off the app.
