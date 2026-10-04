#!/usr/bin/env bash
# Auto-allow a read-only `gh api` call, so the ask rule on `gh api` fires only for writes.
# Anything this script cannot prove is a lone GET stays silent and falls through to that rule.
# See docs/design/gh-api-read-allow.md
command -v jq >/dev/null 2>&1 || exit 0
cmd="$(jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -n "$cmd" ] || exit 0

# Print the line's words one per line with quotes resolved. Exit 1 when the shell would
# see more than words: an operator, an expansion, a second line, or an open quote.
words() {
  printf '%s' "$1" | awk '
    BEGIN { sq = sprintf("%c", 39); dq = sprintf("%c", 34); bs = sprintf("%c", 92); nt = 0 }
    NR > 1 { bad = 1; exit }
    {
      q = ""; w = ""; inw = 0
      for (i = 1; i <= length($0); i++) {
        c = substr($0, i, 1)
        if (q == sq) { if (c == sq) q = ""; else w = w c; continue }
        if (c == bs) { i++; w = w substr($0, i, 1); inw = 1; continue }
        if (q == dq) {
          if (c == dq) q = ""
          else if (c == "$" || c == "`") { bad = 1; exit }
          else w = w c
          continue
        }
        if (c == sq || c == dq) { q = c; inw = 1; continue }
        if (c == " " || c == "\t") { if (inw) { t[nt++] = w; w = ""; inw = 0 }; continue }
        if (index(";|&<>()$`", c)) { bad = 1; exit }
        w = w c; inw = 1
      }
      if (q != "") { bad = 1; exit }
      if (inw) t[nt++] = w
    }
    END { if (bad) exit 1; for (k = 0; k < nt; k++) print t[k] }'
}

out="$(words "$cmd")" || exit 0
toks=()
while IFS= read -r w; do toks+=("$w"); done <<<"$out"
[ "${toks[0]:-}" = gh ] && [ "${toks[1]:-}" = api ] || exit 0

# An allowlist, not the write denylist in lib/publish-cmd.sh. An allow decision bypasses
# every permission rule, so an unknown flag must stay a prompt.
i=2; endpoint=""
while [ "$i" -lt "${#toks[@]}" ]; do
  case "${toks[$i]}" in
    -X | --method) [ "${toks[$((i + 1))]:-}" = GET ] || exit 0; i=$((i + 2)); continue ;;
    -XGET | --method=GET) ;;
    -H | --header | -q | --jq | -t | --template | --cache) i=$((i + 2)); continue ;;
    --header=* | --jq=* | --template=* | --cache=*) ;;
    -i | --include | --paginate | --silent | --slurp | --verbose) ;;
    -*) exit 0 ;;
    *) [ -z "$endpoint" ] || exit 0; endpoint="${toks[$i]}" ;;
  esac
  i=$((i + 1))
done
# A full URL can carry the token to a host that is not GitHub. Only a path is a read here.
case "$endpoint" in "" | *://*) exit 0 ;; esac

printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"read-only gh api GET"}}'
