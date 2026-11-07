---
name: snow-report
description: Use when answering "how many / which / trend" questions about ServiceNow data, such as counts by group, breakdowns, top-N lists, and date-range trends on incidents, changes, requests, or any table. Fully read-only; works on every deployment.
---

# ServiceNow reporting

Everything here is read-only. Two tools do the work: `aggregate_stats` for
numbers, `query_records` for the rows behind them. Operator syntax is in
`using-snow`'s `references/encoded-queries.md`. Unfamiliar table? Call
`describe_table` first.

## Recipes

- **Count by group** ("open incidents per assignment group"):
  `aggregate_stats(table="incident", query="active=true", group_by="assignment_group")`
- **Trend over time** ("incidents opened per week, last month"): group by a
  date field and bucket client-side, or run one count per window:
  `aggregate_stats(table="incident", query="sys_created_on>=javascript:gs.beginningOfLastMonth()^sys_created_on<javascript:gs.beginningOfThisMonth()")`
- **Averages/extremes**: `aggregate_stats(..., avg_fields="reassignment_count")`,
  `min_fields`/`max_fields`/`sum_fields` for numeric columns.
- **Top-N list** (newest first, capped):
  `query_records(table="incident", query="active=true^ORDERBYDESCsys_created_on", limit=10, fields=[...])`
  Always pass `fields=`: full records drown the useful columns.
- **Percentage**: run two counts (subset and total) and divide; there is no
  ratio aggregate.

## Habits that keep reports honest

**Counts are not readable rows.** snow-mcp asks ServiceNow as the user and
scopes nothing itself: the rows a call returns are the ones the user's ACLs
let them read, while `total_matching` (in a `query_records` result) and
every `aggregate_stats` figure are ServiceNow's counts of matching records,
which may include records the user cannot read (the server does not
establish which). Never present a count as the number of records the user
can read. To tell, when `total_matching` is 500 or less, run the query
again with a `limit` of at least `total_matching`: the page then holds the
whole match, and a `count` below `total_matching`, or an `aggregate_stats`
count above that `count`, means the counts include records the user cannot
read; say so. A null `total_matching` means the instance sent no count: say
the total is unknown.

- For "how many", quote `total_matching` or the `aggregate_stats` count,
  not the page length, and call it the number of matching records.
- An empty `query_records` page is not proof of zero activity: the user's
  ACLs may hide every matching row.
- Choice fields group by raw value; map labels via `describe_table`'s choice
  lists before presenting.
- Prefer one `aggregate_stats` with `group_by` over N per-group queries.
