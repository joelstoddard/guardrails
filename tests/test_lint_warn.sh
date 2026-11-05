#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/helper.sh"
S="$DIR/../plugins/building/hooks/scripts/lint-warn.sh"
json() { printf '{"cwd":"%s","tool_input":{"command":"%s"}}' "$1" "$2"; }
# A hook with no cwd falls back to the directory it runs in, so the suite runs from a scratch repo whose lint
# fails: the fallback can never run the caller's real lint, and a test that reaches it shows.
here="$(make_repo main)"
printf '## Commands\n- **Lint:** `false`\n' > "$here/AGENTS.md"; commit_doc "$here"
cd "$here" || exit 1

# Failing lint on commit → NEVER blocks (rc 0) but emits a warning on stdout
rf="$(make_repo main)"; git -C "$rf" switch -q -c nbc-1-x
printf '## Commands\n- **Lint:** `false`\n' > "$rf/AGENTS.md"; commit_doc "$rf"
run_hook "$S" "$(json "$rf" "git commit -m x")"
assert_rc 0 "lint failure never blocks"
assert_out "additionalContext" "warning emitted as JSON"
assert_out "Lint" "warning mentions lint"

# Passing lint → silent allow
rp="$(make_repo main)"; git -C "$rp" switch -q -c nbc-2-y
printf '## Commands\n- **Lint:** `true`\n' > "$rp/AGENTS.md"; commit_doc "$rp"
run_hook "$S" "$(json "$rp" "git commit -m x")"
assert_rc 0 "passing lint allowed"
assert_eq "$OUT" "" "passing lint warns nothing"

# Hooks run outside Claude Code's sandbox, so a command from an agent doc edited since the last commit does not run (#83).
ran="$(scratch_dir)/ran"
printf '## Commands\n- **Lint:** `touch %s; false`\n' "$ran" > "$rp/AGENTS.md"
run_hook "$S" "$(json "$rp" "git commit -am x")"
assert_eq "$OUT" "" "the committed lint command runs"
[ ! -e "$ran" ] || { echo "  FAIL [a modified agent doc's command does not run]: $ran exists"; FAILS=1; }

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
printf '## Commands\n- **Lint:** `cat >/dev/null`\n' > "$rs/AGENTS.md"; commit_doc "$rs"
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

# Past 64 directories the hook could time out, so it judges the first 64, then warns. A cwd of one directory per
# line is printed back as the walk's directories, so it stands in for a command that commits in many.
many() { local d="$1" n="$2"; shift 2; jq -cn --arg cwd "$(for x in "$@"; do printf '%s\n' "$x"; done; for _ in $(seq "$n"); do printf '%s\n' "$d"; done)" \
  '{cwd:$cwd,tool_input:{command:"git commit -m x"}}'; }
run_hook "$S" "$(many "$rp" 64)"
assert_eq "$OUT" "" "64 directories whose lint passes warn nothing"
run_hook "$S" "$(many "$rp" 65)"
assert_rc 0 "65 directories never block"
assert_out "more than 64 directories" "past 64 directories the hook warns it could not judge them all"
run_hook "$S" "$(many "$rp" 64 "$rf")"
assert_out "Lint failed in $(cd "$rf" && pwd -P)" "a lint failure within the first 64 directories still warns"
case "$OUT" in *"more than 64"*) echo "  FAIL [a lint failure is the one warning]: $OUT"; FAILS=1 ;; esac

# With no cwd in its input, the hook judges the directory it runs in.
run_hook "$S" '{"tool_input":{"command":"git commit -m x"}}'
assert_out "$here" "with no cwd, the hook judges the directory it runs in: a scratch repo, never the caller's"

finish "lint-warn"
