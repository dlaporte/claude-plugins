# servicenow changelog

What each release of the plugin changed, oldest first.

## 1.0.0

The first release: six skills over the snow-mcp server's per-user OAuth
(`using-snow`, which every other skill loads first and which probes the
deployment's read-only mode and tool packages, then `snow-triage`,
`snow-change`, `snow-order`, `snow-kb` and `snow-report`), with the server's
encoded-query helper allowlist documented and the version bump enforced in
CI.

## 1.0.1

Plugin 1.0.1 says what a count is: `using-snow` and `snow-report` now share
one paragraph saying that the rows a call returns are what the user's ACLs
allow, while `total_matching` and `aggregate_stats` are ServiceNow's counts of
matching records and may include records the user cannot read, so a count is
never reported as readable rows, a page that holds the whole match shows the
difference, and a null `total_matching` is an unknown total (this replaces
using-snow's "what they can see matches the UI" and snow-report's "counts ALL
matching records", read from snow-mcp's source at v1.0.0). `using-snow` names
the generic table tools (`list_tables`, `create_record` and `delete_record`
with `confirm=true`), and `snow-order` names the catalog item types as `type=`
values. No em or en dash remains anywhere in the plugin, and `snow-report`'s
not-equal sign is words. The README's install section points at the
repository README's, the one home for install commands. CI checks every tool
name the plugin uses against snow-mcp's tool list, pinned at v1.0.0 in
`scripts/snow-tools.txt`, in both directions.
