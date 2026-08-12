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

finish "guard-default-branch"
