#!/usr/bin/env bash
# At SubagentStop, keep a subagent's findings for the main session's Stop gate, because a
# background subagent's report never reaches a main-session hook. Fail-open on missing jq.
command -v jq >/dev/null 2>&1 || exit 0
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SELF_DIR/../../lib/findings.sh"
umask 077 # findings can describe vulnerabilities
input="$(cat)"
field() { printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null; }
dir="$(_guardrails_pending_dir "$(field .session_id)")" || exit 0

# One file per subagent, so a retry after a rejected report replaces the first one.
id="$(field .agent_id)"
[ -n "$id" ] || id="capture-$$-$RANDOM" # without an agent_id, every report is kept
_guardrails_token "$id" || exit 0
items="$(_guardrails_findings "$(field .last_assistant_message)")"
[ -n "$items" ] || { rm -f "$dir/$id"; exit 0; }
agent="$(field .agent_type)"
mkdir -p "$dir"
printf '%s\n' "$items" | awk -v a="${agent:-subagent}" '{ print "[" a "] " $0 }' > "$dir/.$id.tmp" &&
  mv "$dir/.$id.tmp" "$dir/$id"
exit 0
