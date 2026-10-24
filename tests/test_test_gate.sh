#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/helper.sh"
S="$DIR/../plugins/building/hooks/scripts/test-gate.sh"
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

# Regression: "git push" inside an argument must NOT trigger the gate (rf has failing tests)
run_hook "$S" "$(json "$rf" "echo about to git push then stop")"
assert_rc 0 "git push inside an argument not gated"

# Escape hatch
export SKIP_TEST_GATE=1
run_hook "$S" "$(json "$rf" "git push origin HEAD")"
assert_rc 0 "escape hatch allows"
unset SKIP_TEST_GATE

# A push inside a shell payload is a push (#65).
run_hook "$S" "$(json "$rf" "bash -c 'git push origin HEAD'")"
assert_rc 2 "push inside bash -c gated"

# The gate judges the repo git pushes from, not the one the session sits in (#75).
run_hook "$S" "$(json "$rf" "git -C $r push origin HEAD")"
assert_rc 0 "git -C a repo whose tests pass, from one whose tests fail, pushes"
run_hook "$S" "$(json "$r" "git -C $rf push origin HEAD")"
assert_rc 2 "git -C a repo whose tests fail is blocked"
assert_err "$rf" "the block names the repo"
run_hook "$S" "$(json "$r" "cd $rf && git push origin HEAD")"
assert_rc 2 "cd into a repo whose tests fail, then push, is blocked"

# Where the two splits disagree on the directory, each repo is judged, and only once (#75).
split_cd() { jq -cn --arg cwd "$1" --arg c $'x=a; echo "${x#"\'"}"\ncd '"$2"$'\n# \'\ngit push origin HEAD' \
  '{cwd:$cwd,tool_input:{command:$c}}'; }
run_hook "$S" "$(split_cd "$r" "$rf")"
assert_rc 2 "a failing repo only the per-line split cds into is blocked"
rn1="$(make_repo main)"; count="$(scratch_file)"
printf '## Commands\n- **Test:** `echo run >> %s`\n' "$count" > "$rn1/AGENTS.md"
run_hook "$S" "$(split_cd "$rn1" .)"
assert_eq "$(wc -l < "$count" | tr -d ' ')" "1" "one repo reached by both splits runs its tests once"
rs="$(make_repo main)"
printf '## Commands\n- **Test:** `cat >/dev/null`\n' > "$rs/AGENTS.md"
run_hook "$S" "$(split_cd "$rs" "$rf")"
assert_rc 2 "a test command reading stdin does not hide the next repo"

finish "test-gate"
