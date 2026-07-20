#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/helper.sh"
S="$DIR/../hooks/scripts/guard-default-branch.sh"

json() { printf '{"cwd":"%s","tool_input":{"command":"%s"}}' "$1" "$2"; }

# On default branch (main) → block a commit
r="$(make_repo main)"
run_hook "$S" "$(json "$r" "git commit -m x")"
assert_rc 2 "commit on main blocked"
assert_err "default branch" "block reason surfaced"

# On a feature branch → allowed
r2="$(make_repo main)"; git -C "$r2" switch -q -c nbc-1-x
run_hook "$S" "$(json "$r2" "git commit -m x")"
assert_rc 0 "commit on feature branch allowed"

# Non-commit command → allowed (ignored)
run_hook "$S" "$(json "$r" "git status")"
assert_rc 0 "non-commit ignored"

# Escape hatch
export ALLOW_DEFAULT_COMMIT=1
run_hook "$S" "$(json "$r" "git commit -m x")"
assert_rc 0 "escape hatch allows"
unset ALLOW_DEFAULT_COMMIT

finish "guard-default-branch"
