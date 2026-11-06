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
if why="$(_guardrails_unreadable "$cmd")"; then
  dirs="${cwd:-.}"; unsure="Could not read this command in full to check it does not push: $why"
else
  unsure=""
  # A shell reading commands from a pipe may push where no guard can read it, so a failure asks too (#63).
  if ! _guardrails_invokes_git "$cmd" push; then
    why="$(_guardrails_unseen_shell_stdin "$cmd")" || exit 0
    unsure="Could not check this command does not push: $why"
  fi
  # Judge the repo git pushes from, not the one the shell sits in; where the two splits disagree on it,
  # judge both, each once (#75). See docs/design/git-command-parsing.md.
  dirs="$(_guardrails_git_effective_cwd "$cmd" push "${cwd:-.}")"
fi
[ "${SKIP_TEST_GATE:-}" = "1" ] && exit 0

# Each directory costs a git call and may cost a run, so past 64 the hook could time out: it judges 64, then says so.
over="$(printf '%s\n' "$dirs" | awk 'NR > 64 { print 1; exit }')"
while IFS= read -r repo; do
  testcmd="$(repo_cmd "$repo" test)" || {
    echo "⚠️  test-gate: no test command in the committed AGENTS.md or CLAUDE.md of $repo — skipping (CI is the backstop). Document it to enable the local gate." >&2
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
done < <(printf '%s\n' "$dirs" | awk 'NR <= 64' |
  while IFS= read -r dir; do git -C "$dir" rev-parse --show-toplevel 2>/dev/null; done | awk '!seen[$0]++')
if [ -n "$over" ]; then
  jq -cn --arg r "${unsure:+$unsure. }Could not check the tests of every repo this pushes from: it pushes from more than 64 directories, more than the gate can check in time. It checked the first 64." \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'
fi
exit 0
