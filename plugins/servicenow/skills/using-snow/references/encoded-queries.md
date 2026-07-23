# Encoded-query reference

Syntax: `field<op>value` clauses joined by `^`. No spaces around operators.
`^OR` binds to the previous clause; `^NQ` starts a whole new query (top-level
OR). Sorting is part of the query: `^ORDERBY<field>` / `^ORDERBYDESC<field>`.

## Operators

| Operator | Example | Notes |
|---|---|---|
| `=` `!=` | `state=2` | Choice fields use raw values (see describe_table) |
| `>` `>=` `<` `<=` | `priority<=2` | Also works on dates |
| `IN` / `NOT IN` | `stateIN1,2,3` | Comma-separated |
| `LIKE` / `NOT LIKE` | `short_descriptionLIKEvpn` | Contains |
| `STARTSWITH` / `ENDSWITH` | `numberSTARTSWITHINC` | |
| `ISEMPTY` / `ISNOTEMPTY` | `assigned_toISEMPTY` | |
| `BETWEEN` | `sys_created_onBETWEENjavascript:gs.beginningOfLastMonth()@javascript:gs.endOfLastMonth()` | `@`-separated bounds |
| `123TEXTQUERY321` | `123TEXTQUERY321=email outage` | Full-text across the record |
| `SAMEAS` / `NSAMEAS` | `assigned_toSAMEAScaller_id` | Compare two fields |

## Relative dates (`javascript:` helpers evaluate server-side)

- Today / recent: `sys_created_on>=javascript:gs.beginningOfToday()`,
  `sys_created_on>=javascript:gs.daysAgoStart(7)`
- Calendar spans: `gs.beginningOfLastWeek()`, `gs.beginningOfThisMonth()`,
  `gs.beginningOfLastMonth()`…`gs.endOfLastMonth()`, `gs.beginningOfThisQuarter()`
- Current user: `assigned_to=javascript:gs.getUserID()`

Only simple `javascript:gs.<helper>()` calls (optionally one integer
argument) are accepted — the server rejects any other `javascript:`
expression in a query.

## Dot-walking

Reference fields traverse with `.`: `caller_id.department.name=IT`,
`assignment_group.manager=javascript:gs.getUserID()`,
`cmdb_ci.sys_class_name=cmdb_ci_linux_server`. Works in queries and in
`fields` selections.

## Worked examples

- My group's open incidents, newest first:
  `active=true^assignment_group.nameLIKEservice desk^ORDERBYDESCsys_created_on`
- P1/P2 created this week: `priorityIN1,2^sys_created_on>=javascript:gs.beginningOfThisWeek()`
- Unassigned high-urgency: `assigned_toISEMPTY^urgency=1`
- Changes scheduled over a window:
  `start_date<=2026-08-01 00:00:00^end_date>=2026-07-25 00:00:00`
- RITMs under a request: `request=<sc_request sys_id>` on `sc_req_item`
