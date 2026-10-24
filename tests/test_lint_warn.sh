#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/helper.sh"
S="$DIR/../plugins/building/hooks/scripts/lint-warn.sh"
json() { printf '{"cwd":"%s","tool_input":{"command":"%s"}}' "$1" "$2"; }

# Failing lint on commit → NEVER blocks (rc 0) but emits a warning on stdout
rf="$(make_repo main)"; git -C "$rf" switch -q -c nbc-1-x
printf '## Commands\n- **Lint:** `false`\n' > "$rf/AGENTS.md"
run_hook "$S" "$(json "$rf" "git commit -m x")"
assert_rc 0 "lint failure never blocks"
assert_out "additionalContext" "warning emitted as JSON"
assert_out "Lint" "warning mentions lint"

# Passing lint → silent allow
rp="$(make_repo main)"; git -C "$rp" switch -q -c nbc-2-y
printf '## Commands\n- **Lint:** `true`\n' > "$rp/AGENTS.md"
run_hook "$S" "$(json "$rp" "git commit -m x")"
assert_rc 0 "passing lint allowed"

# The hook judges the repo git commits in, not the one the session sits in (#75).
run_hook "$S" "$(json "$rp" "git -C $rf commit -m x")"
assert_out "additionalContext" "git -C a repo whose lint fails warns"
assert_out "$rf" "the warning names the repo"
run_hook "$S" "$(json "$rf" "cd $rp && git commit -m x")"
assert_eq "$OUT" "" "cd into a repo whose lint passes, from one whose lint fails, warns nothing"

# Where the two splits disagree on the directory, each repo is judged (#75).
split_cd() { jq -cn --arg cwd "$1" --arg c $'x=a; echo "${x#"\'"}"\ncd '"$2"$'\n# \'\ngit commit -m x' \
  '{cwd:$cwd,tool_input:{command:$c}}'; }
rs="$(make_repo main)"; git -C "$rs" switch -q -c nbc-3-z
printf '## Commands\n- **Lint:** `cat >/dev/null`\n' > "$rs/AGENTS.md"
run_hook "$S" "$(split_cd "$rs" "$rf")"
assert_out "$rf" "a lint command reading stdin does not hide the next repo"

# A command too long or dense to read in time may commit, so the session's repo is judged (#103).
long="$(printf '%s' "git status $(printf '%0263000d' 0)" | jq -cRs --arg cwd "$rf" '{cwd:$cwd,tool_input:{command:.}}')"
run_hook "$S" "$long"
assert_out "additionalContext" "an unreadable command warns when lint fails"
assert_out "Could not read" "the warning says why"
run_hook "$S" "$(printf '%s' "$long" | jq -c --arg cwd "$rp" '.cwd = $cwd')"
assert_eq "$OUT" "" "an unreadable command warns nothing when lint passes"

# A shell reading commands from a pipe may commit where no guard can read it (#63).
run_hook "$S" "$(json "$rf" "cat cmds.txt | bash")"
assert_out 'reads commands from stdin' "a pipe into a shell warns, saying why, when lint fails"
run_hook "$S" "$(json "$rp" "cat cmds.txt | bash")"
assert_eq "$OUT" "" "a pipe into a shell warns nothing when lint passes"

finish "lint-warn"
