#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/helper.sh"
S="$DIR/../plugins/building/hooks/scripts/guard-default-branch.sh"

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

# Regression: "git commit" appearing inside an argument must NOT block on the default branch
r3="$(make_repo main)"
run_hook "$S" "$(json "$r3" "gh pr create --base main --body 'body mentions git commit here'")"
assert_rc 0 "git commit inside an argument not blocked"

# Regression: a chained real commit on the default branch IS still blocked
r4="$(make_repo main)"
run_hook "$S" "$(json "$r4" "git add -A && git commit -m x")"
assert_rc 2 "chained commit on default branch blocked"

# --- `git -C <path>`: judge the repo git acts on, not the shell's cwd ---
# The motivating false positive: one worktree per ticket, shell sits in the primary checkout
# on main, and `git -C <worktree> commit` was refused against the primary checkout's branch.
r5="$(make_repo main)"
git -C "$r5" worktree add -q -b nbc-2-y "$r5/../wt-$$" >/dev/null 2>&1
wt="$(cd "$r5/../wt-$$" && pwd)"
run_hook "$S" "$(json "$r5" "git -C $wt commit -m x")"
assert_rc 0 "commit into a feature-branch worktree allowed from a main checkout"

# ...and the converse must still be caught: -C pointing AT the default branch is blocked.
r6="$(make_repo main)"; r6b="$(make_repo main)"; git -C "$r6b" switch -q -c nbc-3-z
run_hook "$S" "$(json "$r6b" "git -C $r6 commit -m x")"
assert_rc 2 "commit -C into a default-branch repo blocked from a feature-branch cwd"

# A relative -C resolves against the payload cwd.
r7="$(make_repo main)"
run_hook "$S" "$(json "$r7/.." "git -C $(basename "$r7") commit -m x")"
assert_rc 2 "relative -C resolved against cwd"

# --- `cd <path> && git commit`: the form that actually caused the false positive ---
# The payload cwd never moves, so before this the guard read the primary checkout's branch.
r8="$(make_repo main)"
git -C "$r8" worktree add -q -b nbc-4-w "$r8/../wt8-$$" >/dev/null 2>&1
wt8="$(cd "$r8/../wt8-$$" && pwd)"
run_hook "$S" "$(json "$r8" "cd $wt8 && git commit -m x")"
assert_rc 0 "cd into a feature-branch worktree then commit allowed"

# ...and cd-ing INTO a default-branch repo is still blocked.
r9="$(make_repo main)"; r9b="$(make_repo main)"; git -C "$r9b" switch -q -c nbc-5-v
run_hook "$S" "$(json "$r9b" "cd $r9 && git commit -m x")"
assert_rc 2 "cd into a default-branch repo then commit blocked"

# A bare `cd` must not be treated as a redirect to somewhere permissive.
r10="$(make_repo main)"
run_hook "$S" "$(json "$r10" "cd && git commit -m x")"
assert_rc 2 "bare cd does not smuggle a default-branch commit past the guard"

# A cd only the per-line split sees still sends the guard there: a misread quote must not hide it.
r11="$(make_repo main)"; r11b="$(make_repo main)"; git -C "$r11b" switch -q -c nbc-6-u
run_hook "$S" "$(jq -cn --arg cwd "$r11b" --arg c $'x=a; echo "${x#"\'"}"\ncd '"$r11"$'\n# \'\ngit commit -m x' \
  '{cwd:$cwd,tool_input:{command:$c}}')"
assert_rc 2 "cd into a default-branch repo hidden by a misread quote blocked"

# A command the guard cannot read in full might cd anywhere and commit, so it asks (#64, #76).
r12="$(make_repo main)"; git -C "$r12" switch -q -c nbc-7-t
long="git status $(printf '%0263000d' 0)"
run_hook "$S" "$(printf '%s' "$long" | jq -cRs --arg cwd "$r12" '{cwd:$cwd,tool_input:{command:.}}')"
assert_rc 0 "a command too long to read is not refused outright"
assert_out '"permissionDecision":"ask"' "a command too long to read asks"
broken="$(scratch_dir)"; printf '#!/bin/sh\nexit 2\n' > "$broken/awk"; chmod +x "$broken/awk"
old="$PATH"; export PATH="$broken:$PATH"
run_hook "$S" "$(json "$r12" "git commit -m x")"
export PATH="$old"
assert_out '"permissionDecision":"ask"' "a split that aborts asks"
export ALLOW_DEFAULT_COMMIT=1
run_hook "$S" "$(printf '%s' "$long" | jq -cRs --arg cwd "$r12" '{cwd:$cwd,tool_input:{command:.}}')"
assert_eq "$OUT" "" "the override asks nothing about an unreadable command"
unset ALLOW_DEFAULT_COMMIT

# A commit in a heredoc fed to a shell is a commit (#63).
r13="$(make_repo main)"
run_hook "$S" "$(jq -cn --arg cwd "$r13" --arg c $'bash <<EOF\ngit commit -m x\nEOF' '{cwd:$cwd,tool_input:{command:$c}}')"
assert_rc 2 "a commit in a heredoc fed to bash blocked"

# A pipe into a shell could commit unseen: on a default branch it asks, elsewhere it passes (#63).
r14b="$(make_repo main)"; git -C "$r14b" switch -q -c nbc-8-s
run_hook "$S" "$(json "$r13" "cat cmds.txt | bash")"
assert_rc 0 "a pipe into a shell is not refused outright"
assert_out '"permissionDecision":"ask"' "a pipe into a shell on a default branch asks"
assert_out 'reads commands from stdin' "the question says why"
run_hook "$S" "$(json "$r14b" "cat cmds.txt | bash")"
assert_eq "$OUT" "" "a pipe into a shell off the default branch asks nothing"
export ALLOW_DEFAULT_COMMIT=1
run_hook "$S" "$(json "$r13" "cat cmds.txt | bash")"
assert_eq "$OUT" "" "the override asks nothing about a pipe into a shell"
unset ALLOW_DEFAULT_COMMIT

# A commit inside a shell payload is a commit (#65).
r14="$(make_repo main)"
run_hook "$S" "$(json "$r13" "bash -c 'git commit -m x'")"
assert_rc 2 "a commit inside bash -c on the default branch blocked"
run_hook "$S" "$(json "$r14b" "bash -c 'cd $r14 && git commit -m x'")"
assert_rc 2 "a cd into a default-branch repo inside bash -c blocked"

# A commit inside a command substitution is a commit (#87).
run_hook "$S" "$(jq -cn --arg cwd "$r13" --arg c 'echo "$(git commit -m x)"' '{cwd:$cwd,tool_input:{command:$c}}')"
assert_rc 2 "a commit inside a substitution on the default branch blocked"
run_hook "$S" "$(jq -cn --arg cwd "$r13" --arg c 'x=`git commit -m x`' '{cwd:$cwd,tool_input:{command:$c}}')"
assert_rc 2 "a commit inside backticks on the default branch blocked"

# Many segments, or many shells and evals to re-read, cost far more than their length, so past these
# caps a command might commit unread, and it asks (#94).
jsonat() { printf '%s' "$2" | jq -cRs --arg cwd "$1" '{cwd:$cwd,tool_input:{command:.}}'; }
run_hook "$S" "$(jsonat "$r13" "$(printf 'true\n%.0s' {1..5001})"$'\n''git commit -m x')"
assert_out '"permissionDecision":"ask"' "too many segments to read in time asks"
assert_out 'segments are too many' "the question names the segments"
run_hook "$S" "$(jsonat "$r13" "$(printf 'eval x\n%.0s' {1..17})"$'\n''git commit -m x')"
assert_out '"permissionDecision":"ask"' "too many shells and evals to re-read asks"
run_hook "$S" "$(jsonat "$r13" "$(printf 'true\n%.0s' {1..4998})"$'\n''git commit -m x')"
assert_rc 2 "a commit within the segment cap is still read and refused"

# The segments an eval or sh -c re-reads count against the cap too, at every depth (#107).
run_hook "$S" "$(jsonat "$r13" "eval 'eval \"eval eval $(printf 'a b;%.0s' {1..32700})\"'"$'\n''git commit -m x')"
assert_out '"permissionDecision":"ask"' "nested eval payloads past the segment cap ask"
assert_out 'segments are too many' "the question names the segments in the payloads"
run_hook "$S" "$(jsonat "$r13" $'bash <<\'EOF\'\n'"$(printf 'cp "src/a b.txt" out/\n%.0s' {1..4998})"$'\ngit commit -m x\nEOF')"
assert_rc 2 "a commit at the end of a 5,000-line script fed to bash is read and refused"
# Each depth splits the text again, so the characters a shell or eval reads again count against the length cap (#107).
run_hook "$S" "$(jsonat "$r13" "eval eval eval eval git commit -m x $(printf 'a b %.0s' {1..32690})")"
assert_out '"permissionDecision":"ask"' "four evals over 128 KiB ask"
assert_out 'read again' "the question names the text read again"

finish "guard-default-branch"
