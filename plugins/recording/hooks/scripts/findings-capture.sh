#!/usr/bin/env bash
# At SubagentStop, keep a subagent's findings for the main session's Stop gate, because a
# background subagent's report never reaches a main-session hook. Fail-open on missing jq.
command -v jq >/dev/null 2>&1 || exit 0
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SELF_DIR/../../lib/findings.sh"
input="$(cat)"
file="$(_guardrails_findings_file "$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)")" || exit 0
items="$(_guardrails_findings "$(printf '%s' "$input" | jq -r '.last_assistant_message // empty' 2>/dev/null)")"
[ -n "$items" ] || exit 0
agent="$(printf '%s' "$input" | jq -r '.agent_type // "subagent"' 2>/dev/null)"
mkdir -p "$(dirname "$file")"
printf '%s\n' "$items" | awk -v a="$agent" '{ print "[" a "] " $0 }' >> "$file"
exit 0
