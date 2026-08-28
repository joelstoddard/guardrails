#!/usr/bin/env bash
# Block shell commands that publish content appearing to be authored by the user.
# Permission rules match a command prefix and so miss `gh api`, a token-carrying curl,
# and `sh -c` wrappers; this reads the whole command line. Fail-open on missing jq,
# matching the other hooks in this plugin.
command -v jq >/dev/null 2>&1 || exit 0
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SELF_DIR/../../lib/publish-cmd.sh"
input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -n "$cmd" ] || exit 0

reason="$(_guardrails_publishes_as_user "$cmd")" || exit 0

# The hatch is deliberately environment-only: an assistant can prefix any command it
# writes, so _guardrails_publishes_as_user treats an inline assignment as a bypass.
case "$reason" in
  inline*) ;;
  *) [ "${ALLOW_PUBLISH_AS_ME:-}" = "1" ] && exit 0 ;;
esac

cat >&2 <<EOF
Refusing to publish as you — $reason.

This would appear under your name to other people. Draft the content and let the
human post it, or ask them to run the command themselves.

To allow deliberately, the human (not the assistant) sets ALLOW_PUBLISH_AS_ME=1 in
their own shell environment before starting Claude Code.
EOF
exit 2
