#!/usr/bin/env bash
# Block the end of a turn once while findings are untracked: those in the final message, and
# those subagents reported since the last stop. Rule: "Findings" in ~/.claude/rules/core.md.
command -v jq >/dev/null 2>&1 || exit 0
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SELF_DIR/../../lib/findings.sh"
input="$(cat)"
[ "$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)" = "true" ] && exit 0
msg="$(printf '%s' "$input" | jq -r '.last_assistant_message // empty' 2>/dev/null)"

tracked="$(_guardrails_findings "$msg" | grep -E -- "$_GUARDRAILS_TRACKED_RE")"
pending=""
if file="$(_guardrails_findings_file "$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)")" && [ -f "$file" ]; then
  # A subagent's finding the final message already carries with a reference is done.
  pending="$(awk '!seen[$0]++' "$file" | while IFS= read -r p; do
    printf '%s\n' "$tracked" | grep -qF -- "${p#\[*\] }" || printf '%s\n' "$p"
  done)"
  rm -f "$file"
fi
# ponytail: reads only a "Findings outside scope" heading; findings written under another heading pass.
untracked="$(_guardrails_untracked "$msg")"
[ -n "$pending$untracked" ] || exit 0

reason=""
if [ -n "$pending" ]; then
  reason="Subagents reported these findings outside scope:"
  while IFS= read -r f; do reason="$reason"$'\n'"  - ${f:0:120}"; done <<< "$pending"
  reason="$reason"$'\n'
fi
if [ -n "$untracked" ]; then
  reason="${reason}These findings in your message have no issue reference:"
  while IFS= read -r f; do reason="$reason"$'\n'"  - ${f:0:120}"; done <<< "$untracked"
  reason="$reason"$'\n'
fi
reason="${reason}Track each with the guardrails:track-findings skill. End its line with the issue URL, (asked) while the user decides, or (declined) if they said no."
jq -n --arg r "$reason" '{decision:"block",reason:$r}'
exit 0
