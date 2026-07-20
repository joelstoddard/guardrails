#!/usr/bin/env bash
# Block `git push` when the repo's AGENTS.md-documented test command fails. Fail-open.
command -v jq >/dev/null 2>&1 || exit 0
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SELF_DIR/../../lib/repo-cmd.sh"

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"

case "$cmd" in *"git push"*) ;; *) exit 0 ;; esac
[ "${SKIP_TEST_GATE:-}" = "1" ] && exit 0

repo="$(git -C "${cwd:-.}" rev-parse --show-toplevel 2>/dev/null)" || exit 0
testcmd="$(repo_cmd "$repo" test)" || {
  echo "⚠️  test-gate: no test command documented in $repo/AGENTS.md — skipping (CI is the backstop). Document it to enable the local gate." >&2
  exit 0
}

if ( cd "$repo" && eval "$testcmd" ) >/dev/null 2>&1; then
  exit 0
fi
echo "Tests failed: \`$testcmd\` (from AGENTS.md). Fix them before pushing, or set SKIP_TEST_GATE=1 to override." >&2
exit 2
