#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/helper.sh"
S="$DIR/../hooks/scripts/test-gate.sh"
json() { printf '{"cwd":"%s","tool_input":{"command":"%s"}}' "$1" "$2"; }

# Repo with a passing test command → push allowed
r="$(make_repo main)"
printf '## Commands\n- **Test:** `true`\n' > "$r/AGENTS.md"
run_hook "$S" "$(json "$r" "git push origin HEAD")"
assert_rc 0 "push allowed when tests pass"

# Repo with a failing test command → push blocked
rf="$(make_repo main)"
printf '## Commands\n- **Test:** `false`\n' > "$rf/AGENTS.md"
run_hook "$S" "$(json "$rf" "git push origin HEAD")"
assert_rc 2 "push blocked when tests fail"
assert_err "Tests failed" "block reason surfaced"

# No test command documented → push allowed (fail-open) with a warning
rn="$(make_repo main)"
run_hook "$S" "$(json "$rn" "git push origin HEAD")"
assert_rc 0 "no test cmd → allowed"

# git commit (not push) → ignored by this gate
run_hook "$S" "$(json "$r" "git commit -m x")"
assert_rc 0 "commit ignored by push gate"

# Escape hatch
export SKIP_TEST_GATE=1
run_hook "$S" "$(json "$rf" "git push origin HEAD")"
assert_rc 0 "escape hatch allows"
unset SKIP_TEST_GATE

finish "test-gate"
