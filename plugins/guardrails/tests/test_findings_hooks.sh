#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/helper.sh"
GATE="$DIR/../hooks/scripts/findings-gate.sh"
CAPTURE="$DIR/../hooks/scripts/findings-capture.sh"
export XDG_STATE_HOME="$(mktemp -d)"
PENDING="$XDG_STATE_HOME/claude-guardrails/findings/s1"

stop() { jq -n --arg m "$1" --argjson a "${2:-false}" '{session_id:"s1", last_assistant_message:$m, stop_hook_active:$a}'; }
sub() { jq -n --arg m "$1" --arg s "${2:-s1}" '{session_id:$s, agent_type:"sre", last_assistant_message:$m}'; }

untracked='Done.
### Findings outside scope
- The cache never expires'
run_hook "$GATE" "$(stop "$untracked")"
assert_rc 0 "gate exits 0"
assert_out '"decision": "block"' "untracked finding blocks"
assert_out "The cache never expires" "reason names the finding"

run_hook "$GATE" "$(stop "$untracked" true)"
assert_eq "" "$OUT" "stop_hook_active lets it through"

run_hook "$GATE" "$(stop '### Findings outside scope
- The cache never expires https://github.com/o/r/issues/3
- Shared repo lint gap (asked)')"
assert_eq "" "$OUT" "tracked and asked findings pass"

report='## Result: DONE
### Findings outside scope
- Retries are unbounded
- TTL unset'
run_hook "$CAPTURE" "$(sub "$report")"
assert_rc 0 "capture never blocks"
assert_eq "" "$OUT" "capture is silent"
assert_eq "[sre] Retries are unbounded
[sre] TTL unset" "$(cat "$PENDING")" "capture keeps the persona's findings for the session"

run_hook "$CAPTURE" "$(sub "$report")"
run_hook "$GATE" "$(stop 'All done.')"
assert_out '"decision": "block"' "pending persona findings block the main stop"
assert_out "[sre] Retries are unbounded" "reason lists the persona's findings"
assert_eq "1" "$(printf '%s' "$OUT" | grep -o 'Retries are unbounded' | grep -c .)" "a repeated capture is listed once"
[ -e "$PENDING" ] && { echo "  FAIL [gate consumes the pending file]"; FAILS=1; }

run_hook "$GATE" "$(stop 'All done.')"
assert_eq "" "$OUT" "consumed findings do not block again"

run_hook "$CAPTURE" "$(sub "$report" '../escape')"
[ -e "$XDG_STATE_HOME/claude-guardrails/escape" ] && { echo "  FAIL [unsafe session id is ignored]"; FAILS=1; }

run_hook "$CAPTURE" "$(sub '## Result: DONE')"
[ -e "$PENDING" ] && { echo "  FAIL [no findings, nothing kept]"; FAILS=1; }

run_hook "$GATE" '{}'
assert_eq "" "$OUT" "no message, no opinion"

finish "findings-hooks"
