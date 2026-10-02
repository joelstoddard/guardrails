#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/helper.sh"
S="$DIR/../hooks/scripts/persona-report.sh"

stop() { jq -n --arg m "$1" --argjson a "${2:-false}" '{agent_type:"architect", last_assistant_message:$m, stop_hook_active:$a}'; }

good='Work done.

## Result: DONE
### Changes
None.
### Checks run
- make test-unit: OK
### Rules not satisfied or skipped
None.
### Findings outside scope
None.
### Drafts for the user to send
None.
### Questions for the user
None.'
# sed, not ${var/pattern/}: a bash pattern starting with # anchors to the string start.
edit() { printf '%s\n' "$good" | sed "$1"; }

run_hook "$S" "$(stop "$good")"
assert_eq "" "$OUT" "full report passes"

run_hook "$S" "$(stop "$(edit 's/^### Checks run$/### Checks run   /')")"
assert_eq "" "$OUT" "trailing space on a heading passes"

run_hook "$S" "$(stop "$(edit '/^## Result/d')")"
assert_out '"decision": "block"' "missing Result blocks"
assert_out "## Result: DONE | PARTIAL | BLOCKED" "reason shows the Result line"

run_hook "$S" "$(stop "$(edit 's/^## Result: DONE$/## Result: MAYBE/')")"
assert_out '"decision": "block"' "unknown status blocks"

run_hook "$S" "$(stop "$(edit '/^### Checks run$/d')")"
assert_out "### Checks run" "missing heading named"

run_hook "$S" "$(stop "$(edit '/^## Result/d')" true)"
assert_eq "" "$OUT" "stop_hook_active lets it through"

run_hook "$S" '{"agent_type":"architect"}'
assert_eq "" "$OUT" "no message, no opinion"

finish "persona-report"
