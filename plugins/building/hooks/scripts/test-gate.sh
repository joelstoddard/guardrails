#!/usr/bin/env bash
# Block `git push` when the test command from the repo's agent doc fails. Fail-open.
command -v jq >/dev/null 2>&1 || exit 0
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SELF_DIR/../../lib/repo-cmd.sh"
. "$SELF_DIR/../../lib/git-cmd.sh"

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"

# A command too long or dense to read in time may push, so the session's repo is judged, and as it may
# push nothing, a failure asks (#103).
if unsure="$(_guardrails_unreadable "$cmd")"; then
  dirs="${cwd:-.}"; unsure="Could not read this command in full to check it does not push: $unsure"
else
  unsure=""
  _guardrails_invokes_git "$cmd" push || exit 0
  # Judge the repo git pushes from, not the one the shell sits in; where the two splits disagree on it,
  # judge both, each once (#75). See docs/design/git-command-parsing.md.
  dirs="$(_guardrails_git_effective_cwd "$cmd" push "${cwd:-.}")"
fi
[ "${SKIP_TEST_GATE:-}" = "1" ] && exit 0

while IFS= read -r repo; do
  testcmd="$(repo_cmd "$repo" test)" || {
    echo "⚠️  test-gate: no test command in $repo/AGENTS.md or CLAUDE.md — skipping (CI is the backstop). Document it to enable the local gate." >&2
    continue
  }
  ( cd "$repo" && eval "$testcmd" ) </dev/null >/dev/null 2>&1 && continue
  if [ -n "$unsure" ]; then
    jq -cn --arg r "$unsure. Tests fail in $repo (\`$testcmd\` from its agent doc), so allow it only if it pushes nothing." \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'
    exit 0
  fi
  echo "Tests failed in $repo: \`$testcmd\` (from its agent doc). Fix them before pushing, or set SKIP_TEST_GATE=1 to override." >&2
  exit 2
done < <(printf '%s\n' "$dirs" |
  while IFS= read -r dir; do git -C "$dir" rev-parse --show-toplevel 2>/dev/null; done | awk '!seen[$0]++')
exit 0
