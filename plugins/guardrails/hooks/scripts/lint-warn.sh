#!/usr/bin/env bash
# Warn (never block) when the repo's AGENTS.md lint command fails at commit. Fail-open.
command -v jq >/dev/null 2>&1 || exit 0
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SELF_DIR/../../lib/repo-cmd.sh"

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"

case "$cmd" in *"git commit"*) ;; *) exit 0 ;; esac
repo="$(git -C "${cwd:-.}" rev-parse --show-toplevel 2>/dev/null)" || exit 0
lintcmd="$(repo_cmd "$repo" lint)" || exit 0

if ( cd "$repo" && eval "$lintcmd" ) >/dev/null 2>&1; then
  exit 0
fi
jq -n --arg c "⚠️ Lint failed (\`$lintcmd\` from AGENTS.md). Committing anyway — fix before pushing." \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$c}}'
exit 0
