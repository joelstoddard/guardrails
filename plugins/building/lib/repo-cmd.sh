#!/usr/bin/env bash
# repo-cmd.sh — resolve a repo's canonical test/lint command from its agent doc, as
# committed at HEAD. AGENTS.md is the source of truth, and CLAUDE.md is the fallback
# for repos that use that name. No runner is hardcoded.
# Usage: repo_cmd <dir> <test|lint>  → prints command (rc 0) or nothing (rc 1).

# Extract a labelled inline-code command, e.g.  "- **Test:** `make test`"  or
# "Lint: `ruff check .`". Case-insensitive; first match wins. Portable (BSD grep).
#
# The remainder after the label must be EXACTLY one inline-code span, because a
# run-on prose line yields a string that is not a program.
# See docs/design/agent-doc-command-extraction.md
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
  local dir="$1" kind="$2" doc cmd
  # The hooks run it outside Claude Code's sandbox, so only the committed doc names it (#83).
  # See docs/design/agent-doc-command-extraction.md
  for doc in AGENTS.md CLAUDE.md; do
    cmd="$(_guardrails_labelled <(git -C "$dir" cat-file blob "HEAD:$doc" 2>/dev/null) "$kind")"
    [ -n "$cmd" ] && { printf '%s\n' "$cmd"; return 0; }
  done
  return 1
}
