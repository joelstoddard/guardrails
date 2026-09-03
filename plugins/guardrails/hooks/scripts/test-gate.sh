#!/usr/bin/env bash
# Block `git push` when the test command from the repo's agent doc fails. Fail-open.
command -v jq >/dev/null 2>&1 || exit 0
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SELF_DIR/../../lib/repo-cmd.sh"
. "$SELF_DIR/../../lib/git-cmd.sh"

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"

_guardrails_invokes_git "$cmd" push || exit 0
[ "${SKIP_TEST_GATE:-}" = "1" ] && exit 0

repo="$(git -C "${cwd:-.}" rev-parse --show-toplevel 2>/dev/null)" || exit 0
testcmd="$(repo_cmd "$repo" test)" || {
  echo "⚠️  test-gate: no test command in $repo/AGENTS.md or CLAUDE.md — skipping (CI is the backstop). Document it to enable the local gate." >&2
  exit 0
}

if ( cd "$repo" && eval "$testcmd" ) >/dev/null 2>&1; then
  exit 0
fi
echo "Tests failed: \`$testcmd\` (from the repo agent doc). Fix them before pushing, or set SKIP_TEST_GATE=1 to override." >&2
exit 2
