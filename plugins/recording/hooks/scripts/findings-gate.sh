#!/usr/bin/env bash
# Block the end of a turn while findings are untracked: those in the final message, and those
# subagents reported. Rule: "Findings" in the recording plugin's rules/findings.md.
command -v jq >/dev/null 2>&1 || exit 0
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SELF_DIR/../../lib/findings.sh"
umask 077
input="$(cat)"
field() { printf '%s' "$input" | jq -r "$1 // empty" 2>/dev/null; }
active="$(field .stop_hook_active)"
msg="$(field .last_assistant_message)"
tracked="$(_guardrails_findings "$msg" | _guardrails_split tracked)"

# Pending findings stay until a stop passes clean, so findings the model ignored come back next turn.
# ponytail: a capture that lands while this rewrites the same subagent's file is lost; a lock if it happens.
pending=""
if dir="$(_guardrails_pending_dir "$(field .session_id)")" && [ -d "$dir" ]; then
  for f in "$dir"/*; do
    [ -f "$f" ] || continue
    # A subagent's finding the final message already carries with a reference is done.
    left="$(while IFS= read -r p; do
      printf '%s\n' "$tracked" | grep -qF -- "${p#\[*\] }" || printf '%s\n' "$p"
    done < "$f")"
    if [ -n "$left" ]; then printf '%s\n' "$left" > "$f"; else rm -f "$f"; fi
  done
  pending="$(cat "$dir"/* 2>/dev/null | awk '!seen[$0]++')"
fi

if [ "$active" = "true" ]; then
  # A continuation blocks only on findings this turn has not shown yet, so the gate cannot loop.
  [ -n "$pending" ] && [ -f "$dir/.shown" ] && pending="$(printf '%s\n' "$pending" | grep -vxF -f "$dir/.shown")"
  untracked=""
else
  # ponytail: reads only a "Findings outside scope" heading; findings written under another heading pass.
  untracked="$(_guardrails_untracked "$msg")"
fi
if [ -z "$pending$untracked" ]; then
  [ "$active" = "true" ] || [ -z "$dir" ] || rm -rf "$dir"
  exit 0
fi
if [ -n "$pending" ]; then
  if [ "$active" = "true" ]; then printf '%s\n' "$pending" >> "$dir/.shown"; else printf '%s\n' "$pending" > "$dir/.shown"; fi
fi

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
reason="${reason}Track each with the recording:track-findings skill. End its line with the issue URL, (asked) while the user decides, or (declined) if they said no."
jq -n --arg r "$reason" '{decision:"block",reason:$r}'
exit 0
