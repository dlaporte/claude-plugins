# Common tables

Most work records extend `task` — task fields (number, state,
short_description, assigned_to, assignment_group, priority, active,
opened_at) exist on all of them, and `my_work` spans them all.

| Table | Holds | Key fields beyond task |
|---|---|---|
| `incident` | Incidents (INC) | caller_id, category, impact/urgency→priority, close_code/close_notes |
| `change_request` | Changes (CHG) | type, chg_model, risk, start_date/end_date (planned), conflict_status |
| `change_task` | CTASKs under a change | change_request (parent), planned_start_date/planned_end_date |
| `sc_request` | Catalog orders (REQ) | requested_for, stage |
| `sc_req_item` | Items in an order (RITM) | request (parent), cat_item, stage; variables live on the RITM |
| `sc_task` | Fulfillment tasks under a RITM | request_item (parent) |
| `sc_cat_item` | Catalog item *definitions* | name, category, active (read-only browsing; order via catalog tools) |
| `kb_knowledge` | KB articles | kb_knowledge_base, workflow_state (draft/review/published/retired), text |
| `sysapproval_approver` | Approval records | sysapproval (the task), approver, state (requested/approved/rejected) |
| `sys_user` | People | user_name, email, department, manager |
| `sys_user_group` | Groups | name, manager; membership in `sys_user_grmember` |
| `cmdb_ci` | Configuration items (base class) | sys_class_name discriminates subtypes; relations in `cmdb_rel_ci` |
| `sys_journal_field` | Journal entries (comments/work notes) | query `element_id=<record sys_id>`; the Table API doesn't return journals inline |
| `sys_update_set` | Update sets (dev) | state; complete via commit_update_set |

Chain to remember for catalog orders: `sc_request` → `sc_req_item` →
`sc_task`. Chain for changes: `change_request` → `change_task`.
