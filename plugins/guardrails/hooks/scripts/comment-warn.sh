#!/usr/bin/env bash
# Warn (never block) when an edit writes a comment block over the two-sentence cap.
# The concise-comments skill is edit-scoped, so it needs an edit-time trigger to fire.
command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"
file="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"

# Markdown headings and prose read as comment markers, so text formats stay out.
case "$file" in
  *.md|*.markdown|*.rst|*.txt|*.json|*.lock|"") exit 0 ;;
esac

added="$(printf '%s' "$input" | jq -r '
  [.tool_input.new_string?, .tool_input.content?, (.tool_input.edits[]?.new_string)]
  | map(select(. != null)) | join("\n")' 2>/dev/null)"
[ -n "$added" ] || exit 0

hits="$(printf '%s\n' "$added" | awk '
function flush(   s, c) {
  if (buf != "") {
    s = buf " "
    gsub(/[0-9]\.[0-9]/, "0", s)
    gsub(/e\.g\.|i\.e\.|etc\.|vs\./, "X", s)
    c = 0
    while (match(s, /[.!?][ \t]/)) { c++; s = substr(s, RSTART + RLENGTH) }
    if (c > 2) printf "%d\t%s\n", c, first
  }
  buf = ""; first = ""
}
{
  line = $0; sub(/^[ \t]+/, "", line)
  body = ""
  if (line ~ /^#[^!]/)      body = substr(line, 2)
  else if (line ~ /^\/\//)  body = substr(line, 3)
  else if (line ~ /^--[^-]/) body = substr(line, 3)
  sub(/^[ \t]+/, "", body)
  if (body ~ /^(SPDX-|Copyright)/) body = ""
  if (body == "") { flush(); next }
  if (first == "") first = body
  buf = buf " " body
}
END { flush() }')"
[ -n "$hits" ] || exit 0

msg="⚠️ concise-comments rule 4 (two sentences at most) in $file:"
while IFS=$'\t' read -r count snippet; do
  n="$(grep -nF -m1 -- "$snippet" "$file" 2>/dev/null | cut -d: -f1)"
  msg="$msg"$'\n'"  ${file}${n:+:$n} — $count sentences: ${snippet:0:60}"
done <<< "$hits"
msg="$msg"$'\n'"Invoke the guardrails:concise-comments skill: cut it to two sentences, or move the rationale to docs/design/ and leave a pointer."
msg="$msg"$'\n'"Rule 4 does not reach an interface description: a module header, or a function's parameters and usage. Leave those as they are."

jq -n --arg c "$msg" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$c}}'
exit 0
