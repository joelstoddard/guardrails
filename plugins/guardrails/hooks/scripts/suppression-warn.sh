#!/usr/bin/env bash
# Warn (never block) when an edit adds a skipped test or a lint or type suppression.
# One is allowed only for a proven false positive, so the agent must say why.
command -v jq >/dev/null 2>&1 || exit 0
input="$(cat)"
file="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
case "$file" in
  *.md|*.markdown|*.rst|*.txt|"") exit 0 ;;
esac
added="$(printf '%s' "$input" | jq -r '
  [.tool_input.new_string?, .tool_input.content?, (.tool_input.edits[]?.new_string)]
  | map(select(. != null)) | join("\n")' 2>/dev/null)"
[ -n "$added" ] || exit 0

pattern='(^|[^A-Za-z0-9_])(it|test|describe|context|suite)\.skip\(|(^|[^A-Za-z0-9_])xit\(|@pytest\.mark\.skip|t\.Skip\(|#[[:space:]]*noqa|eslint-disable|@ts-ignore|type:[[:space:]]*ignore|as any([];),.}>]|$)|nolint'
hits="$(printf '%s\n' "$added" | grep -E -- "$pattern")" || exit 0

msg="⚠️ skipped test or suppression added in $file:"
while IFS= read -r line; do
  n="$(grep -nF -m1 -- "$line" "$file" 2>/dev/null | cut -d: -f1)"
  trimmed="${line#"${line%%[![:space:]]*}"}"
  msg="$msg"$'\n'"  ${file}${n:+:$n} — ${trimmed:0:80}"
done <<< "$hits"
msg="$msg"$'\n'"NEVER skip a test OR suppress a finding to get past a gate. Keep it ONLY for a proven false positive, scoped to that one finding, with a comment saying WHY."
jq -n --arg c "$msg" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$c}}'
exit 0
