#!/usr/bin/env bash
# Warn (never block) when the lint command from the repo's agent doc fails. Fail-open.
command -v jq >/dev/null 2>&1 || exit 0
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SELF_DIR/../../lib/repo-cmd.sh"
. "$SELF_DIR/../../lib/git-cmd.sh"

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"

_guardrails_invokes_git "$cmd" commit || exit 0
# Judge the repo git commits in, not the one the shell sits in; where the two splits disagree on it,
# judge both, each once (#75). See docs/design/git-command-parsing.md.
while IFS= read -r repo; do
  lintcmd="$(repo_cmd "$repo" lint)" || continue
  ( cd "$repo" && eval "$lintcmd" ) </dev/null >/dev/null 2>&1 && continue
  jq -n --arg c "⚠️ Lint failed in $repo (\`$lintcmd\` from its agent doc). Committing anyway — fix before pushing." \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$c}}'
  exit 0
done < <(_guardrails_git_effective_cwd "$cmd" commit "${cwd:-.}" |
  while IFS= read -r dir; do git -C "$dir" rev-parse --show-toplevel 2>/dev/null; done | awk '!seen[$0]++')
exit 0
