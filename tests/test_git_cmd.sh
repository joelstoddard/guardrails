#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/helper.sh"
. "$DIR/../plugins/building/lib/git-cmd.sh"

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

# A carried quote turns any misread into hidden lines, so $'...' and # end only where the shell ends them.
yes $'printf $\'a\\n\'\ngit commit -m x\n# \'' commit "an a inside \$'...' does not end it"
yes 'echo \;#; git commit -m x'                commit "a # after an escaped ; is mid-word"
yes 'echo $(true)#; git commit -m x'           commit "a # after \$( ) is mid-word"

# A heredoc is recognised by the delimiter the shell reads, and <<< opens none.
yes $'cat <<\\EOF\nWe don\'t ship this yet.\nEOF\ngit commit -m x # it\'s done' commit "a backslash-quoted delimiter opens a heredoc"
yes $'cat <<EOF \\\n  > /dev/null\nbody\nEOF\ngit commit -m x'                commit "a heredoc body starts after its joined line"
yes $'read -r b <<<"$PWD"\ngit commit -m x'                                    commit "a here-string opens no heredoc"

# What the per-line split sees still counts, so a quote the carried split misreads hides nothing.
yes $'bash -c \'\ncd /tmp\ngit commit -m x\n\''       commit "a commit only the per-line split sees"
yes $'x=a; echo "${x#"\'"}"\ngit commit -m x\n# \''     commit "a commit after misread nested quotes"
cwd $'x=a; echo "${x#"\'"}"\ncd /evil\n# \'\ngit commit -m x' commit /start $'/start\n/evil' \
  "both directories when the splits disagree"
# Backticks end where the shell ends them, so quotes inside them no longer split the two apart (#87).
cwd $'echo "`echo \'"\'`"\ncd /evil\n# \'\ngit commit -m x' commit /start /evil "backticks read as the shell reads them"

# A heredoc fed to a shell is the script it runs (#63).
yes $'bash <<EOF\ngit commit -m x\nEOF'           commit "a heredoc fed to bash"
no  $'cat <<EOF\ngit commit -m x\nEOF'            commit "a heredoc fed to cat is data"

# A shell or eval payload is a script of its own (#65).
yes "bash -c 'git commit -m x'"                   commit "inside bash -c"
yes 'sh -c "cd /x && git push origin HEAD"'       push   "inside sh -c after a cd"
yes $'bash -c \'\nset -e\ngit commit -m x\n\''    commit "inside a multi-line bash -c"
yes "bash -lc 'git commit -m x'"                  commit "a -c inside a cluster of flags"
yes "zsh <<<'git push'"                           push   "a here-string fed to zsh"
yes "eval 'git push'"                             push   "inside eval"
yes "eval eval eval eval git commit -m x"         commit "four levels down"
no  "eval eval eval eval eval git commit -m x"    commit "recursion stops at five levels"
no  "bash -c 'echo git commit'"                   commit "a payload is parsed, not matched"

cwd "bash -c 'cd /x && git commit -m y'"  commit /start /x     "a cd inside the payload"
cwd "bash -c 'cd /x'; git commit -m y"    commit /start /start "a child shell's cd does not last"
cwd "eval 'cd /x'; git commit -m y"       commit /start /x     "eval's cd lasts"

# A command substitution runs, so a git command inside it counts (#87).
yes 'echo "$(git commit -m x)"'           commit "inside a double-quoted substitution"
yes 'x=`git push origin HEAD`'             push   "inside backticks in an assignment"
yes 'cat <(git commit -m x)'               commit "inside a process substitution"
no  "echo '\$(git commit -m x)'"           commit "inside single quotes it is text"
cwd 'x=$(cd /x; pwd); git commit -m y'     commit /start /start "a cd inside a substitution does not last"

# A lone & ends a command (#89).
yes 'true & git commit -m x'               commit "a commit after a lone &"
yes 'git add -A 2>&1 & git push'           push   "a push after a redirect and a lone &"
no  'git status &>/dev/null commit'        commit "&> does not split"

# An unquoted heredoc runs the substitutions in its body (#88).
yes $'cat <<EOF\n$(git commit -m x)\nEOF'      commit "a substitution in an unquoted heredoc body"
no  $'cat <<\'EOF\'\n$(git commit -m x)\nEOF'  commit "a substitution in a quoted heredoc body is text"
cwd $'cd /x && cat <<EOF\n`git commit -m y`\nEOF' commit /start /x "a body substitution runs where the heredoc does"

# A keyword, a wrapper and its options, or a ( before git does not hide it (#90).
yes "sudo git commit -m x"                 commit "behind sudo"
yes "sudo -u root git commit -m x"         commit "behind sudo and an option"
yes "env FOO=1 git commit -m x"            commit "behind env and an assignment"
yes "nohup git push origin HEAD"           push   "behind nohup"
yes "command git commit -m x"              commit "behind command"
yes "time git commit -m x"                 commit "behind time"
yes "if true; then git commit -m x; fi"    commit "after then"
yes "{ git commit -m x; }"                 commit "in a group"
yes "(git commit -m x)"                    commit "in a subshell"
yes "sudo bash -c 'git commit -m x'"       commit "a shell behind sudo"
for w in '!' '{' '(' 'if' 'then' 'elif' 'else' 'while' 'until' 'do' 'nohup' 'command' 'time' 'sudo -n' 'env -i' 'exec -c' 'xargs -0' \
  'ssh -T h bash -c' '2>/dev/null' '> log' 'f()' 'f ()' 'function f' 'case x in *)' 'in a)' 'coproc' 'timeout 5' 'nice -n 5' \
  'stdbuf -oL' 'doas -u r' 'setsid' 'chroot /j' 'docker exec -i c bash -c' 'kubectl exec p -- bash -c' '"env"' '\nohup'; do
  yes "$w git commit -m x"                 commit "seen through $w as a segment's first word"
done
yes "/usr/bin/time -p git commit -m x"     commit "seen through a wrapper by path"
no  "env FOO=1 git status"                 commit "env before another subcommand"
no  "command -v git commit"                commit "command -v runs nothing"
cwd "sudo git -C /x commit"                       commit /start /x     "-C behind a wrapper"
cwd "sudo bash -c 'cd /x && git commit -m y'"     commit /start /x     "a cd in a payload behind a wrapper"
# A cd in a subshell does not last, and one behind a keyword may not run, so neither moves the guard.
cwd "(cd /x); git commit -m y"                    commit /start /start "a subshell's cd does not last"
cwd "if false; then cd /x; fi; git commit -m y"   commit /start /start "a cd behind a keyword is not followed"
cwd "if false; then eval 'cd /x'; fi; git commit -m y" commit /start /start "eval's cd behind a keyword is not followed"

# A redirect before git is not the command, fused to its target or not (#109).
yes '2>/dev/null git commit -m x'          commit "behind a fused fd redirect"
yes '> log git commit -m x'                commit "behind a separate redirect"
yes '&>/dev/null git push'                 push   "behind &>"
yes '<in 2>&1 git commit -F -'             commit "behind an input redirect and 2>&1"
no  '2>/dev/null git status'               commit "a redirect before another subcommand"
yes '10>/dev/null git commit -m x'         commit "behind a redirect of a two-digit fd"
yes '{fd}> log git commit -m x'            commit "behind a redirect of a named fd"
no  '2x>f git commit -m x'                 commit "a word with > that is not a redirect"
cwd '2>/dev/null cd /x; git commit -m y'   commit /start /start "a cd behind a redirect is not followed"

# A function body, a case arm or a coproc runs its command, as does a command behind more wrappers (#110).
yes 'f() { git commit -m x; }; f'          commit "in a function body"
yes 'case x in *) git push;; esac'         push   "in a case arm"
yes 'coproc git commit -m x'               commit "in a coproc"
yes 'timeout 30 git push'                  push   "behind timeout"
yes 'nice -n 5 git commit -m x'            commit "behind nice"
no  'docker exec c git commit -m x'        commit "a commit in a container is not here"
cwd 'timeout 5 cd /x; git commit -m y'     commit /start /start "a cd behind a new wrapper is not followed"
cwd 'f() { cd /x; }; git commit -m y'      commit /start /start "a cd in a function body is not followed"

# A wrapper's long option can take the next word as its value; written with = it takes none (#116).
yes 'sudo --user root git commit -m x'     commit "behind sudo --user"
yes 'env --chdir /x git push'              push   "behind env --chdir"
yes 'sudo --user=root git commit -m x'     commit "behind sudo --user=root"
no  'sudo --user git status'               commit "a long option's value is not the command"

# The shell drops the quotes and backslashes of a command word, so a quoted or escaped one is read as itself (#111).
yes '"git" commit -m x'                    commit "a quoted git"
yes '\git commit -m x'                     commit "an escaped git"
yes "'bash' -c 'git commit -m x'"          commit "a quoted shell's payload"
no  '"echo" git commit'                    commit "a quoted text tool"
cwd '"cd" /x; git commit -m y'             commit /start /start "a quoted cd is not followed"

finish "git-cmd"
