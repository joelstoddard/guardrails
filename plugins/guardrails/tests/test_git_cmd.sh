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

# --- subcommand must match: a commit is not a push and vice-versa ---
no "git commit -m 'then git push it'" push   "commit with 'git push' in message is not a push"
no "git status"                       commit "non-commit git subcommand"
no "git pushup"                       push   "similar-but-different subcommand"

# --- accepted limitation: global options before the subcommand are NOT parsed, so
#     `git -C <path> commit` is intentionally not matched (a fail-open guardrail bypass) ---
no "git -C /some/path commit -m x" commit "git -C <path> commit not matched (accepted bypass)"

finish "git-cmd"
