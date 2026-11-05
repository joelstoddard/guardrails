#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/helper.sh"
S="$DIR/../plugins/building/hooks/scripts/test-gate.sh"
json() { printf '{"cwd":"%s","tool_input":{"command":"%s"}}' "$1" "$2"; }
# A hook with no cwd falls back to the directory it runs in, so the suite runs from scratch: the fallback can
# never run the caller's real test command, which here would be this suite again.
cd "$(scratch_dir)" || exit 1

# Repo with a passing test command → push allowed
r="$(make_repo main)"
printf '## Commands\n- **Test:** `true`\n' > "$r/AGENTS.md"; commit_doc "$r"
run_hook "$S" "$(json "$r" "git push origin HEAD")"
assert_rc 0 "push allowed when tests pass"

# Repo with a failing test command → push blocked
rf="$(make_repo main)"
printf '## Commands\n- **Test:** `false`\n' > "$rf/AGENTS.md"; commit_doc "$rf"
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
printf '## Commands\n- **Test:** `echo run >> %s`\n' "$count" > "$rn1/AGENTS.md"; commit_doc "$rn1"
run_hook "$S" "$(split_cd "$rn1" .)"
assert_eq "$(wc -l < "$count" | tr -d ' ')" "1" "one repo reached by both splits runs its tests once"
rs="$(make_repo main)"
printf '## Commands\n- **Test:** `cat >/dev/null`\n' > "$rs/AGENTS.md"; commit_doc "$rs"
run_hook "$S" "$(split_cd "$rs" "$rf")"
assert_rc 2 "a test command reading stdin does not hide the next repo"

# A command too long or dense to read in time may push, so the session's repo is judged, and a failure
# asks rather than blocks, as the command may push nothing (#103).
long="$(printf '%s' "git status $(printf '%0263000d' 0)" | jq -cRs --arg cwd "$rf" '{cwd:$cwd,tool_input:{command:.}}')"
run_hook "$S" "$long"
assert_rc 0 "an unreadable command is not refused outright"
assert_out '"permissionDecision":"ask"' "an unreadable command asks when the tests fail"
assert_out 'Could not read' "the question says why"
run_hook "$S" "$(printf '%s' "$long" | jq -c --arg cwd "$r" '.cwd = $cwd')"
assert_eq "$OUT" "" "an unreadable command asks nothing when the tests pass"
export SKIP_TEST_GATE=1
run_hook "$S" "$long"
assert_eq "$OUT" "" "the escape hatch asks nothing about an unreadable command"
unset SKIP_TEST_GATE

# A shell reading commands from a pipe may push where no guard can read it, so a failure asks (#63).
run_hook "$S" "$(json "$rf" "cat cmds.txt | bash")"
assert_rc 0 "a pipe into a shell is not refused outright"
assert_out '"permissionDecision":"ask"' "a pipe into a shell asks when the tests fail"
assert_out 'reads commands from stdin' "the question says why"
run_hook "$S" "$(json "$r" "cat cmds.txt | bash")"
assert_eq "$OUT" "" "a pipe into a shell asks nothing when the tests pass"

# Past 64 directories the gate could time out, so it judges the first 64, then asks. A cwd of one directory per
# line is printed back as the walk's directories, so it stands in for a command that pushes from many.
many() { local d="$1" n="$2"; shift 2; jq -cn --arg cwd "$(for x in "$@"; do printf '%s\n' "$x"; done; for _ in $(seq "$n"); do printf '%s\n' "$d"; done)" \
  '{cwd:$cwd,tool_input:{command:"git push origin HEAD"}}'; }
run_hook "$S" "$(many "$r" 64)"
assert_eq "$RC:$OUT" "0:" "64 directories whose tests pass push"
run_hook "$S" "$(many "$r" 65)"
assert_rc 0 "65 directories are not refused outright"
assert_out '"permissionDecision":"ask"' "past 64 directories the gate asks"
assert_out 'more than 64 directories' "the question says why"
run_hook "$S" "$(many "$r" 64 "$rf")"
assert_rc 2 "a failure within the first 64 directories still blocks"

# Hooks run outside Claude Code's sandbox, so a command from an agent doc edited since the last commit does not run (#83).
rd="$(make_repo main)"; ran="$(scratch_dir)/ran"
printf '## Commands\n- **Test:** `true`\n' > "$rd/AGENTS.md"; commit_doc "$rd"
printf '## Commands\n- **Test:** `touch %s; false`\n' "$ran" > "$rd/AGENTS.md"
run_hook "$S" "$(json "$rd" "git push origin HEAD")"
assert_rc 0 "the committed test command runs"
[ ! -e "$ran" ] || { echo "  FAIL [a modified agent doc's command does not run]: $ran exists"; FAILS=1; }

finish "test-gate"
