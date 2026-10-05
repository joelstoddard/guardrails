#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/helper.sh"
S="$DIR/../plugins/personas/hooks/scripts/persona-report.sh"

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

run_hook "$S" "$(stop "$(printf '```markdown\n%s\n```' "$good")")"
assert_out '"decision": "block"' "a report wrapped in a fence blocks, as findings-capture cannot read it"

run_hook "$S" "$(stop "$(printf 'The format:\n```\n## Result: DONE\n```\n\n%s' "$good")")"
assert_eq "" "$OUT" "a fenced example before the real report passes"

# A persona that ends by calling the hand-back tool leaves its report in that call, not in
# last_assistant_message (#2), so the hook reads the transcript's last assistant turn.
handback_transcript() {  # <report> → a transcript whose last assistant turn hands the report back
  local t; t="$(scratch_file)"
  { jq -nc '{type:"assistant", message:{role:"assistant", content:[{type:"text", text:"Working on it."}]}}'
    jq -nc --arg m "$1" '{type:"assistant", message:{role:"assistant", content:[{type:"tool_use", name:"SubagentHandback", input:{message:$m}}]}}'
    jq -nc '{type:"user", message:{role:"user", content:[{type:"tool_result", content:"delivered"}]}}'; } > "$t"
  printf '%s\n' "$t"
}
handback_stop() { jq -n --arg m "$1" --arg t "$2" '{agent_type:"architect", last_assistant_message:$m, agent_transcript_path:$t, stop_hook_active:false}'; }

run_hook "$S" "$(handback_stop "" "$(handback_transcript "$good")")"
assert_eq "" "$OUT" "a full report handed back passes, though last_assistant_message is empty"
run_hook "$S" "$(handback_stop "Working on it." "$(handback_transcript "$good")")"
assert_eq "" "$OUT" "a full report handed back passes, though the last text said something else"
run_hook "$S" "$(handback_stop "" "$(handback_transcript "$(edit '/^### Checks run$/d')")")"
assert_out "### Checks run" "a handed-back report missing a heading blocks"

# The personas plugin cannot source the recording plugin's lib, so it keeps a copy of the fence rule.
lib_copy="$(sed -n '/^_guardrails_unfence() {/,/^}/p' "$DIR/../plugins/recording/lib/findings.sh")"
hook_copy="$(sed -n '/^_guardrails_unfence() {/,/^}/p' "$S")"
[ -n "$lib_copy" ] || { echo "  FAIL [unfence copy]: no _guardrails_unfence in recording/lib/findings.sh"; FAILS=1; }
assert_eq "$lib_copy" "$hook_copy" "persona-report's _guardrails_unfence matches the recording lib's"
lib_copy="$(sed -n '/^_guardrails_handback() {/,/^}/p' "$DIR/../plugins/recording/lib/findings.sh")"
hook_copy="$(sed -n '/^_guardrails_handback() {/,/^}/p' "$S")"
[ -n "$lib_copy" ] || { echo "  FAIL [handback copy]: no _guardrails_handback in recording/lib/findings.sh"; FAILS=1; }
assert_eq "$lib_copy" "$hook_copy" "persona-report's _guardrails_handback matches the recording lib's"

finish "persona-report"
