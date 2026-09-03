#!/usr/bin/env bash
# repo-cmd.sh — resolve a repo's canonical test/lint command from its agent doc.
# AGENTS.md is the source of truth, and CLAUDE.md is the fallback for repos that
# use that name. No runner is hardcoded.
# Usage: repo_cmd <dir> <test|lint>  → prints command (rc 0) or nothing (rc 1).

# Extract a labelled inline-code command, e.g.  "- **Test:** `make test`"  or
# "Lint: `ruff check .`". Case-insensitive; first match wins. Portable (BSD grep).
#
# The remainder after the label must be EXACTLY one inline-code span. A label
# line that runs on into prose is a description, not a command: a CI job summary
# under "- **tests**:" may mention a branch or a label in backticks before ever
# naming the command, and lifting the first span out of it yields something that
# is not a program. That then fails to run, and a gate built on this reads the
# failure as "your tests are broken" — blocking every push for a documentation
# shape. Matching nothing is the safe outcome, because callers fail open.
_guardrails_labelled() { # $1=file $2=keyword
  local line norm
  while IFS= read -r line; do
    # Drop a leading list marker and all bold markers so the label, its
    # separator and the command are all that remain to match against.
    norm="$(printf '%s' "$line" \
      | sed -e 's/^[[:space:]]*[-*][[:space:]]*//' -e 's/\*\*//g' -e 's/^[[:space:]]*//')"
    printf '%s' "$norm" \
      | grep -qiE "^$2s?[[:space:]]*[:=-][[:space:]]*\`[^\`]+\`[[:space:]]*$" || continue
    printf '%s' "$norm" | grep -oE '`[^`]+`' | head -n1 | tr -d '`'
    return 0
  done < "$1"
  return 1
}

repo_cmd() {
  local dir="$1" kind="$2" top doc cmd
  top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || top="$dir"
  for doc in "$top/AGENTS.md" "$top/CLAUDE.md"; do
    [ -f "$doc" ] || continue
    cmd="$(_guardrails_labelled "$doc" "$kind")"
    [ -n "$cmd" ] && { printf '%s\n' "$cmd"; return 0; }
  done
  return 1
}
