#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/helper.sh"
. "$DIR/../lib/git-cmd.sh"

yes() { _guardrails_invokes_git "$1" "$2"; RC=$?; assert_rc 0 "$3"; }
no()  { _guardrails_invokes_git "$1" "$2"; RC=$?; assert_rc 1 "$3"; }

# --- real git invocations are detected ---
yes "git commit -m x"          commit "plain commit"
yes "git push origin HEAD"     push   "plain push"
yes "/usr/bin/git commit"      commit "absolute git path"
yes "ALLOW=1 git commit -m x"  commit "leading env assignment"

# --- command chains ---
yes "cd /x && git commit -m y"      commit "chain with &&"
yes "git add -A && git commit -m y" commit "add then commit"
yes "false; git push"               push   "chain with ;"

# --- the substring false-positives the old matcher wrongly blocked ---
no "gh pr create --body 'mentions git commit here'" commit "git commit inside an argument"
no "echo git commit"                                commit "git commit as echo text"
no "grep -rn 'git push' ."                          push   "git push inside a grep pattern"

# --- operators inside quotes are data, not shell syntax ---
# Splitting on them blindly fabricates a command that was never run.
no "grep -E 'a|git commit|b' file"   commit "pipe inside a single-quoted pattern"
no 'rg "x|git push" src/'            push   "pipe inside a double-quoted pattern"
no "grep -E 'p;git commit' file"     commit "semicolon inside a pattern"
no "echo 'a && git push'"            push   "&& inside a quoted string"

# ...while real operators outside quotes must still split.
yes "true | git commit -m x"         commit "real pipe still splits"
yes "echo x && git push"             push   "real && still splits"

# --- subcommand must match: a commit is not a push and vice-versa ---
no "git commit -m 'then git push it'" push   "commit with 'git push' in message is not a push"
no "git status"                       commit "non-commit git subcommand"
no "git pushup"                       push   "similar-but-different subcommand"

# --- global options before the subcommand are skipped, so `git -C <path> commit` IS a commit.
#     Previously treated as an accepted bypass; it is not, because a hook that cannot see it
#     judges the wrong repo rather than merely missing one. ---
yes "git -C /some/path commit -m x"        commit "git -C <path> commit"
yes "git --no-pager -C /x commit"          commit "valueless global then -C"
yes "git --git-dir=/x/.git commit"         commit "--opt=value global"
yes "git -c user.name=t commit -m x"       commit "-c name=value global"
yes "git -C /a -C /b push"                 push   "repeated -C"
no  "git -C /some/path status"             commit "globals skipped but subcommand still checked"

# --- effective cwd: which repo git actually runs in, reached by `cd` or by -C ---
cwd() { OUT="$(_guardrails_git_effective_cwd "$1" "$2" "$3")"; assert_eq "$OUT" "$4" "$5"; }

# no redirection → the starting cwd stands
cwd "git commit -m x"            commit /start /start "plain commit keeps cwd"
cwd "echo git -C /x commit"      commit /start /start "not a git invocation, cwd untouched"

# -C
cwd "git -C /abs commit"         commit /start /abs        "-C absolute"
cwd "git -C sub commit"          commit /start /start/sub  "-C relative to cwd"
cwd "git -C /a -C /b commit"     commit /start /b          "repeated -C folds in order"
cwd "git -c user.name=t commit"  commit /start /start      "-c is not -C"

# cd — the form that actually bit: payload cwd never moves
cwd "cd /wt && git commit -m x"  commit /start /wt         "cd absolute then commit"
cwd "cd sub && git commit"       commit /start /start/sub  "cd relative then commit"
cwd "cd /a && cd /b && git commit" commit /start /b        "chained cd"
cwd "cd && git commit"           commit /start /start      "bare cd not guessed at"
cwd "cd - && git commit"         commit /start /start      "cd - not guessed at"

# the two compose, and -C wins when absolute
cwd "cd /a && git -C /b commit"  commit /start /b          "cd then absolute -C"
cwd "cd /a && git -C sub commit" commit /start /a/sub      "cd then relative -C"

# a cd for a different subcommand must not be attributed to ours
cwd "cd /a && git push"          commit /a     /a          "cd applies, but no matching commit"

# A `cd` fabricated out of a quoted pattern must not redirect the guard. This is the
# sharp end of blind splitting: guard-default-branch would resolve a path that does not
# exist, fail to read a branch from it, and let a commit on the default branch through.
cwd "grep -E 'x|cd /evil' f && git commit -m y" commit /start /start "fabricated cd from a pattern ignored"
cwd "echo 'cd /evil; git commit' && git commit" commit /start /start "fabricated cd and commit both ignored"

finish "git-cmd"
