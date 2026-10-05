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

# Fail closed: a command the guard cannot read in full gets a question, not a pass.
if why="$(_guardrails_unreadable "$cmd")"; then
  [ "${ALLOW_PUBLISH_AS_ME:-}" = "1" ] && exit 0
  jq -cn --arg r "Could not read this command to check it does not publish as you: $why. Allow it only if nothing here posts under your name." \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'
  exit 0
fi

reason="$(_guardrails_publishes_as_user "$cmd")" || {
  # Read line by line, as before quotes carried, it may still publish: a quote spanning lines
  # looks the same as shell syntax the carried split misreads, so only the human can tell.
  reason="$(_GUARDRAILS_SPLIT_PER_LINE=1 _guardrails_publishes_as_user "$cmd")" || exit 0
  [ "${ALLOW_PUBLISH_AS_ME:-}" = "1" ] && exit 0
  jq -cn --arg r "Could not be sure this does not publish as you. Read line by line: $reason. A quoted argument spanning lines reads the same way, so allow it only if nothing here posts under your name." \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'
  exit 0
}

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
