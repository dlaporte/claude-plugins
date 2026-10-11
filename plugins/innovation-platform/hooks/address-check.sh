#!/usr/bin/env bash
# SessionStart: if the platform address option is unset, tell Claude how to fix it.
# Prints nothing when the address is set.
if [ -z "${CLAUDE_PLUGIN_OPTION_PLATFORM_URL:-}" ]; then
  cat <<'JSON'
{"systemMessage":"innovation-platform: set your platform address. Your platform's panel shows the command on its Connect Claude Code card.","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"The innovation-platform plugin has no platform address yet, so its inno-platform tools are not connected. Tell the user to open their platform's panel, copy the configure command from its Connect Claude Code card, run it in a terminal, and restart Claude Code. Inside Claude Code, /plugin configure innovation-platform also sets it."}}
JSON
fi
exit 0
