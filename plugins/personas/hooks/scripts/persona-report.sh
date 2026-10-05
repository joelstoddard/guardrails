#!/usr/bin/env bash
# Hold a persona at SubagentStop until its final message carries the report format from
# the persona protocol in the personas plugin's rules. Fail-open on missing jq.
command -v jq >/dev/null 2>&1 || exit 0

# A copy of the recording plugin's _guardrails_unfence, which this plugin cannot source; a test keeps
# them equal. findings-capture reads only unfenced text, so a heading inside a fence must not count.
_guardrails_unfence() {
  printf '%s\n' "$1" | awk '
    function run(s) { match(s, /^[[:space:]]*(```+|~~~+)/); s = substr(s, RSTART, RLENGTH); sub(/^[[:space:]]*/, "", s); return s }
    { line[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) {
        o = run(line[i])
        if (o == "") { print line[i]; continue }
        for (j = i + 1; j <= NR; j++) {
          c = run(line[j])
          if (substr(c, 1, 1) == substr(o, 1, 1) && length(c) >= length(o) && line[j] ~ /^[[:space:]]*(`+|~+)[[:space:]]*$/) break
        }
        if (j <= NR) i = j; else print line[i]
      }
    }'
}

input="$(cat)"
[ "$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)" = "true" ] && exit 0
msg="$(printf '%s' "$input" | jq -r '.last_assistant_message // empty' 2>/dev/null)"
[ -n "$msg" ] || exit 0
msg="$(_guardrails_unfence "$msg")"

# ponytail: matches on agent name, so a repo's own agent named like a persona is held once too.
missing=""
printf '%s\n' "$msg" | grep -qE '^## Result: (DONE|PARTIAL|BLOCKED)[[:space:]]*$' ||
  missing="$missing"$'\n'"  - ## Result: DONE | PARTIAL | BLOCKED"
for h in "Changes" "Checks run" "Rules not satisfied or skipped" "Findings outside scope" \
  "Drafts for the user to send" "Questions for the user"; do
  printf '%s\n' "$msg" | grep -qE "^### ${h}[[:space:]]*$" || missing="$missing"$'\n'"  - ### $h"
done
[ -n "$missing" ] || exit 0

reason="Your report is missing:$missing"$'\n'"End with the report format in the persona protocol, every heading present (write None. under an empty one)."
jq -n --arg r "$reason" '{decision:"block",reason:$r}'
exit 0
