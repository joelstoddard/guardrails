#!/usr/bin/env bash
# repo-cmd.sh — resolve a repo's canonical test/lint command from its AGENTS.md.
# The repo's AGENTS.md is the single source of truth; no runner is hardcoded.
# Usage: repo_cmd <dir> <test|lint>  → prints command (rc 0) or nothing (rc 1).

# Extract a labelled inline-code command, e.g.  "- **Test:** `make test`"  or
# "Lint: `ruff check .`". Case-insensitive; first match wins. Portable (BSD grep).
_guardrails_labelled() { # $1=file $2=keyword
  grep -iE "^[[:space:]]*([-*][[:space:]]*)?(\*\*)?$2s?(\*\*)?[[:space:]]*[:=-]" "$1" 2>/dev/null \
    | grep -oE '`[^`]+`' | head -n1 | tr -d '`'
}

repo_cmd() {
  local dir="$1" kind="$2" top agents cmd
  top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || top="$dir"
  agents="$top/AGENTS.md"
  [ -f "$agents" ] || return 1
  cmd="$(_guardrails_labelled "$agents" "$kind")"
  [ -n "$cmd" ] || return 1
  printf '%s\n' "$cmd"
}
