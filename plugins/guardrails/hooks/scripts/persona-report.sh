#!/usr/bin/env bash
# Hold a persona at SubagentStop until its final message carries the report format from
# ~/.claude/rules/delegation.md. Fail-open on missing jq.
command -v jq >/dev/null 2>&1 || exit 0
input="$(cat)"
[ "$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)" = "true" ] && exit 0
msg="$(printf '%s' "$input" | jq -r '.last_assistant_message // empty' 2>/dev/null)"
[ -n "$msg" ] || exit 0

# ponytail: matches on agent name, so a repo's own agent named like a persona is held once too.
missing=""
printf '%s\n' "$msg" | grep -qE '^## Result: (DONE|PARTIAL|BLOCKED)[[:space:]]*$' ||
  missing="$missing"$'\n'"  - ## Result: DONE | PARTIAL | BLOCKED"
for h in "Changes" "Checks run" "Rules not satisfied or skipped" "Findings outside scope" \
  "Drafts for the user to send" "Questions for the user"; do
  printf '%s\n' "$msg" | grep -qE "^### $h[[:space:]]*$" || missing="$missing"$'\n'"  - ### $h"
done
[ -n "$missing" ] || exit 0

reason="Your report is missing:$missing"$'\n'"End with the report format in ~/.claude/rules/delegation.md, every heading present (write None. under an empty one)."
jq -n --arg r "$reason" '{decision:"block",reason:$r}'
exit 0
