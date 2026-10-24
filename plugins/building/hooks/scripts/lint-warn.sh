#!/usr/bin/env bash
# Warn (never block) when the lint command from the repo's agent doc fails. Fail-open.
command -v jq >/dev/null 2>&1 || exit 0
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SELF_DIR/../../lib/repo-cmd.sh"
. "$SELF_DIR/../../lib/git-cmd.sh"

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"

# A command too long or dense to read in time may commit, so the session's repo is judged (#103).
if why="$(_guardrails_unreadable "$cmd")"; then
  dirs="${cwd:-.}"; unsure="Could not read this command in full to check it does not commit: $why. "
else
  unsure=""
  # A shell reading commands from a pipe may commit where no guard can read it (#63).
  if ! _guardrails_invokes_git "$cmd" commit; then
    why="$(_guardrails_unseen_shell_stdin "$cmd")" || exit 0
    unsure="Could not check this command does not commit: $why. "
  fi
  # Judge the repo git commits in, not the one the shell sits in; where the two splits disagree on it,
  # judge both, each once (#75). See docs/design/git-command-parsing.md.
  dirs="$(_guardrails_git_effective_cwd "$cmd" commit "${cwd:-.}")"
fi

while IFS= read -r repo; do
  lintcmd="$(repo_cmd "$repo" lint)" || continue
  ( cd "$repo" && eval "$lintcmd" ) </dev/null >/dev/null 2>&1 && continue
  jq -n --arg c "⚠️ ${unsure}Lint failed in $repo (\`$lintcmd\` from its agent doc). Committing anyway — fix before pushing." \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$c}}'
  exit 0
done < <(printf '%s\n' "$dirs" |
  while IFS= read -r dir; do git -C "$dir" rev-parse --show-toplevel 2>/dev/null; done | awk '!seen[$0]++')
exit 0
