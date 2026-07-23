---
name: snow-report
description: Use when answering "how many / which / trend" questions about ServiceNow data — counts by group, breakdowns, top-N lists, date-range trends on incidents, changes, requests, or any table. Fully read-only; works on every deployment.
---

# ServiceNow reporting

Everything here is read-only. Two tools do the work: `aggregate_stats` for
numbers, `query_records` for the rows behind them. Operator syntax:
`using-snow` → `references/encoded-queries.md`. Unfamiliar table? —
`describe_table` first.

## Recipes

- **Count by group** — "open incidents per assignment group":
  `aggregate_stats(table="incident", query="active=true", group_by="assignment_group")`
- **Trend over time** — "incidents opened per week, last month": group by a
  date field and bucket client-side, or run one count per window:
  `aggregate_stats(table="incident", query="sys_created_on>=javascript:gs.beginningOfLastMonth()^sys_created_on<javascript:gs.beginningOfThisMonth()")`
- **Averages/extremes** — `aggregate_stats(..., avg_fields="reassignment_count")`,
  `min_fields`/`max_fields`/`sum_fields` for numeric columns.
- **Top-N list** — newest first, capped:
  `query_records(table="incident", query="active=true^ORDERBYDESCsys_created_on", limit=10, fields=[...])`
  Always pass `fields=` — full records drown the useful columns.
- **Percentage** — run two counts (subset and total) and divide; there is no
  ratio aggregate.

## Habits that keep reports honest

- `query_records` returns `total_matching` — quote it, not the page length.
- Choice fields group by raw value; map labels via `describe_table`'s choice
  lists before presenting.
- ACLs scope `query_records` rows, so an empty list ≠ zero activity —
  but `aggregate_stats` counts ALL matching records (totals can exceed
  the rows you can read); note the difference when they disagree.
- Prefer one `aggregate_stats` with `group_by` over N per-group queries.
