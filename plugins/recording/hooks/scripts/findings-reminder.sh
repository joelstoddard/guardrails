#!/usr/bin/env bash
# At each prompt, name how many subagent findings wait for a findings list, which the Stop gate
# holds silently until one comes. A note, never a block; fail-open on missing jq.
command -v jq >/dev/null 2>&1 || exit 0
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SELF_DIR/../../lib/findings.sh"
dir="$(_guardrails_pending_dir "$(jq -r '.session_id // empty' 2>/dev/null)")" || exit 0
# Counted as the gate reads them: every subagent's file, each finding once.
n="$(cat "$dir"/* 2>/dev/null | awk '!seen[$0]++ { n++ } END { print n + 0 }')"
[ "$n" -gt 0 ] || exit 0
echo "$n subagent finding(s) are pending. When this request is done, list them under a \"Findings outside scope\" heading; the Stop hook names each one it does not see tracked."
exit 0
