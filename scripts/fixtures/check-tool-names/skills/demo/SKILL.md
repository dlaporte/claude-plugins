---
name: demo
description: A fixture for scripts/test-check-tool-names.sh, not a skill. It lists tools as skills do (register_app, app_status, set_app_variables/list_app_variables) and one misspelling joined by a slash (list_app_variables/set_app_variabl).
---

# Lines that must FAIL (the test expects exactly these)

- A misspelling, bare: `list_appz`.
- A misspelling, called: call `get_app_log` next.
- A retired tool with no tool verb, called: the `renew_app` tool.
- A retired tool, called with arguments: `decommission_app({ app })`.
- A retired tool that begins with a tool verb, called: call `create_app`.

```
frobnicate_app({ app })
register_ap({ app, repo })
```

# Lines that must PASS

- Tools, bare and called: `app_status`, call `get_platform_status`, the
  `get_app_logs` MCP tool, `stop_app({ app })`, `set_app_variables {app, variables}`,
  `get_config app=<name>`.
- Arguments, fields, settings keys and codes: `accept_guardrails: true`,
  `accept_guardrails`, `include_admin_group`, `owner_not_revocable`,
  `admin_table_empty`, `safety.stop_pinned`, `start_limit_reached`.
- App code, allowlisted: `current_user(request)`.
- Not a call cue, since "recall" is not "call": recall `foo_bar` later.
- A misspelling with neither a cue nor a tool verb (the known blind spot): `app_statsu`.

```
register_app({ app, repo, description, type, members, accept_guardrails: true })
deploy_it() {
  echo "a shell function definition is not a call"
}
def get_thing(request):
    value = get_thing(request)
{ "set_thing": 1 }
```
