#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/helper.sh"
S="$DIR/../hooks/scripts/guard-publish.sh"

json() { printf '{"tool_input":{"command":"%s"}}' "$1"; }

# --- the motivating case: a comment posted under the user's name ---
run_hook "$S" "$(json 'gh pr comment 12 --body hi')"
assert_rc 2 "gh pr comment blocked"
assert_err "publish" "block reason surfaced"

run_hook "$S" "$(json 'gh issue comment 12 --body hi')"
assert_rc 2 "gh issue comment blocked"

# --- shapes that prefix-matching permission rules cannot see ---
run_hook "$S" "$(json 'gh api -X POST repos/o/r/issues/1/comments -f body=hi')"
assert_rc 2 "gh api POST blocked"

run_hook "$S" "$(json 'sh -c \"gh pr comment 1 --body hi\"')"
assert_rc 2 "sh -c wrapper blocked"

run_hook "$S" "$(json 'git add -A && gh pr review 1 --approve')"
assert_rc 2 "chained publish blocked"

# --- reads stay usable ---
run_hook "$S" "$(json 'gh pr view 12')"
assert_rc 0 "gh pr view allowed"

run_hook "$S" "$(json 'gh api repos/o/r/pulls/1')"
assert_rc 0 "gh api GET allowed"

run_hook "$S" "$(json 'git status')"
assert_rc 0 "unrelated command allowed"

run_hook "$S" '{"tool_input":{}}'
assert_rc 0 "missing command allowed"

# --- the escape hatch, set by the human in their own environment ---
export ALLOW_PUBLISH_AS_ME=1
run_hook "$S" "$(json 'gh pr comment 12 --body hi')"
assert_rc 0 "environment hatch allows"

# ...but an inline assignment is a bypass attempt, blocked even alongside the real hatch.
run_hook "$S" "$(json 'ALLOW_PUBLISH_AS_ME=1 gh pr comment 1 --body x')"
assert_rc 2 "inline hatch assignment still blocked"
unset ALLOW_PUBLISH_AS_ME

# Without the hatch, the inline form is blocked too.
run_hook "$S" "$(json 'ALLOW_PUBLISH_AS_ME=1 gh pr comment 1 --body x')"
assert_rc 2 "inline hatch blocked without env hatch"

finish "guard-publish"
