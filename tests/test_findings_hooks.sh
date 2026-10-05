#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/helper.sh"
GATE="$DIR/../plugins/recording/hooks/scripts/findings-gate.sh"
CAPTURE="$DIR/../plugins/recording/hooks/scripts/findings-capture.sh"
XDG_STATE_HOME="$(scratch_dir)" || exit 1
export XDG_STATE_HOME
PENDING="$XDG_STATE_HOME/claude-guardrails/pending/s1"

stop() { jq -n --arg m "$1" --argjson a "${2:-false}" '{session_id:"s1", last_assistant_message:$m, stop_hook_active:$a}'; }
# sub <message> [session] [agent_id] — a subagent's SubagentStop input
sub() { jq -n --arg m "$1" --arg s "${2:-s1}" --arg i "${3:-a1}" '{session_id:$s, agent_id:$i, agent_type:"sre", last_assistant_message:$m}'; }
report() { printf '## Result: DONE\n### Findings outside scope\n'; printf -- '- %s\n' "$@"; }

untracked='Done.
### Findings outside scope
- The cache never expires'
run_hook "$GATE" "$(stop "$untracked")"
assert_rc 0 "gate exits 0"
assert_out '"decision": "block"' "untracked finding blocks"
assert_out "The cache never expires" "reason names the finding"

run_hook "$GATE" "$(stop "$untracked" true)"
assert_eq "" "$OUT" "stop_hook_active lets the final message's own findings through"

run_hook "$GATE" "$(stop '### Findings outside scope
- The cache never expires https://github.com/o/r/issues/3
- Shared repo lint gap (asked)')"
assert_eq "" "$OUT" "tracked and asked findings pass"

run_hook "$CAPTURE" "$(sub "$(report 'Retries are unbounded' 'TTL unset')")"
assert_rc 0 "capture never blocks"
assert_eq "" "$OUT" "capture is silent"
assert_eq "[sre] Retries are unbounded
[sre] TTL unset" "$(cat "$PENDING/a1")" "capture keeps the subagent's findings for the session"
assert_eq "-rw-------" "$(ls -l "$PENDING/a1" | cut -c1-10)" "pending findings are readable only by the user"

run_hook "$CAPTURE" "$(sub "$(report 'Retries have no upper bound' 'TTL unset')")"
assert_eq "[sre] Retries have no upper bound
[sre] TTL unset" "$(cat "$PENDING/a1")" "a retry replaces the same subagent's earlier report"

run_hook "$CAPTURE" "$(sub "$(report 'Disk fills up' )" s1 a2)"
run_hook "$GATE" "$(stop 'All done.')"
assert_out '"decision": "block"' "pending findings block the main stop"
assert_out "[sre] Retries have no upper bound" "reason lists the first subagent's findings"
assert_out "[sre] Disk fills up" "reason lists the second subagent's findings"
assert_eq "0" "$(printf '%s' "$OUT" | grep -c 'Retries are unbounded')" "the replaced report is gone"
[ -e "$PENDING/a1" ] || { echo "  FAIL [a block keeps the pending findings]"; FAILS=1; }

run_hook "$GATE" "$(stop 'Still not tracked.' true)"
assert_eq "" "$OUT" "a continuation with nothing new is let through, so the gate cannot loop"

run_hook "$CAPTURE" "$(sub "$(report 'Queue has no dead-letter' )" s1 a3)"
run_hook "$GATE" "$(stop 'Still working.' true)"
assert_out "[sre] Queue has no dead-letter" "a finding captured during a continuation blocks that continuation's stop"
assert_eq "0" "$(printf '%s' "$OUT" | grep -c 'Disk fills up')" "findings already shown this turn are not listed again"

run_hook "$GATE" "$(stop 'Next turn.')"
assert_out "[sre] Disk fills up" "findings the model ignored block again at the next turn's stop"

run_hook "$GATE" "$(stop 'Filed them.
### Findings outside scope
- Retries have no upper bound https://github.com/o/r/issues/7
- TTL unset (asked)
- Disk fills up (declined)')"
assert_out "[sre] Queue has no dead-letter" "only the pending finding left untracked is listed"
assert_eq "0" "$(printf '%s' "$OUT" | grep -c 'Retries have no upper bound')" "a tracked one is not"

run_hook "$GATE" "$(stop '### Findings outside scope
- Queue has no dead-letter o/r#9')"
assert_eq "" "$OUT" "once every pending finding is tracked, the stop passes"
[ -e "$PENDING" ] && { echo "  FAIL [a clean stop removes the session's pending findings]"; FAILS=1; }

run_hook "$CAPTURE" "$(sub "$(report 'Flaky test')" s1 a4)"
run_hook "$CAPTURE" "$(sub '## Result: DONE
### Findings outside scope
None.' s1 a4)"
[ -e "$PENDING/a4" ] && { echo "  FAIL [a retry with no findings clears the subagent's earlier ones]"; FAILS=1; }

run_hook "$CAPTURE" "$(sub "$(report 'x')" '../escape')"
[ -e "$XDG_STATE_HOME/claude-guardrails/escape" ] && { echo "  FAIL [unsafe session id is ignored]"; FAILS=1; }
run_hook "$CAPTURE" "$(sub "$(report 'x')" s1 '../../escape')"
[ -e "$XDG_STATE_HOME/claude-guardrails/escape" ] && { echo "  FAIL [unsafe agent id is ignored]"; FAILS=1; }

run_hook "$GATE" '{}'
assert_eq "" "$OUT" "no message, no opinion"

finish "findings-hooks"
