#!/usr/bin/env bash
# Report unpromoted skill lessons older than a week. Reports only — promoting
# rewrites the agent's own instructions and opens a PR, which is not something
# to do unattended. See docs/specs/2026-09-07-guardrails-autonomy-design.md
command -v jq >/dev/null 2>&1 || exit 0
journal="${GUARDRAILS_LESSONS_JOURNAL:-$HOME/.claude/skill-lessons.jsonl}"
[ -f "$journal" ] || exit 0

cutoff="$(date -v-7d +%F 2>/dev/null || date -d '7 days ago' +%F 2>/dev/null)"
[ -n "$cutoff" ] || exit 0

# fromjson? drops malformed lines instead of failing the whole read.
result="$(jq -Rrs '
  [ splits("\n") | select(length > 0) | (fromjson? // empty)
    | select(.promoted != true) | .date // empty ]
  | if length == 0 then empty else "\(length) \(min)" end
' "$journal" 2>/dev/null)"
[ -n "$result" ] || exit 0

count="${result%% *}"
oldest="${result##* }"
[[ "$oldest" < "$cutoff" ]] || exit 0

now="$(date +%s)"
oldest_epoch="$(date -j -f %F "$oldest" +%s 2>/dev/null || date -d "$oldest" +%s 2>/dev/null)"
[ -n "$oldest_epoch" ] || exit 0
days=$(( (now - oldest_epoch) / 86400 ))

echo "$count lesson(s) pending promotion (oldest $days days). Run /guardrails:self-improvement apply."
exit 0
