#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/helper.sh"
. "$DIR/../plugins/building/lib/git-cmd.sh"

yes() { _guardrails_invokes_git "$1" "$2"; RC=$?; assert_rc 0 "$3"; }
no()  { _guardrails_invokes_git "$1" "$2"; RC=$?; assert_rc 1 "$3"; }
# there: git runs the subcommand only on another host or in a container, where a guard cannot judge its repo.
there() { _guardrails_invokes_git "$1" "$2"; RC=$?; assert_rc 2 "$3"; }

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
# walk reads the carried split alone, whose tags place each command, without the per-line split's false positives.
walk() { OUT="$(_guardrails_git_walk_cwd "$1" "$2" "$3" | sed '/^end:/d')"; assert_eq "$OUT" "$4" "$5"; }

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
cwd "cd -P /wt && git commit"    commit /start /wt         "cd's option before its directory"
cwd "cd -LP -- /wt && git commit" commit /start /wt         "cd's options and -- before its directory"
cwd "cd -- -x && git commit"      commit /start /start/-x   "a directory after -- that starts with a dash"
cwd "cd -P && git commit"         commit /start /start      "cd with an option and no directory"
cwd "cd - && git commit"         commit /start /start      "cd - not guessed at"

# pushd changes the directory as cd does, and popd returns to the one before it.
cwd 'pushd /x && git commit -m y'                commit /s /x  "pushd then commit"
cwd 'pushd /x >/dev/null && git commit -m y'     commit /s /x  "pushd with its output redirected"
cwd 'pushd /x && popd && git commit -m y'        commit /s /s  "popd returns"
cwd 'pushd /x && pushd /y && popd && git commit' commit /s /x  "popd returns one level"
cwd 'popd && git commit -m y'                    commit /s /s  "popd with nothing pushed is not guessed at"
cwd 'pushd -n /x && git commit -m y'             commit /s /s  "pushd -n does not change the directory"
cwd 'pushd && git commit -m y'                   commit /s /s  "pushd alone swaps to a directory not known"
cwd 'pushd +1 && git commit -m y'                commit /s /s  "pushd +N rotates to a directory not known"
walk 'pushd /x | true; git commit -m y'          commit /s 'local: /s' "a piped pushd does not last"
cwd '(pushd /x); git commit -m y'                commit /s /s  "a pushd in a subshell does not last"

# the two compose, and -C wins when absolute
cwd "cd /a && git -C /b commit"  commit /start /b          "cd then absolute -C"
cwd "cd /a && git -C sub commit" commit /start /a/sub      "cd then relative -C"

# a cd for a different subcommand must not be attributed to ours
cwd "cd /a && git push"          commit /a     /a          "cd applies, but no matching commit"

# Every matching command is judged, each directory once, not only the first.
cwd "git -C a push && git -C b push"            push   /s $'/s/a\n/s/b' "both pushes' directories"
cwd "git commit -m x; cd /b; git commit -m y"   commit /s $'/s\n/b'     "a commit before and after a cd"
cwd "git -C /a commit; git -C /a commit"        commit /s /a            "one directory judged once"
cwd "bash -c 'git -C /a commit'; git -C /b commit" commit /s $'/a\n/b'  "a commit in a payload and one after it"
cwd "git -C /a commit; cd /c"                   commit /s /a            "the directory after the last command is not judged"

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
for d in 'E\OF' 'E"OF"' "E'OF'"; do
  yes $'cat <<'"$d"$'\nbody\nEOF\ngit commit -m x' commit "the delimiter <<$d is EOF, as the shell reads it (#62)"
done
yes $'cat <<.END\nbody\n.END\ngit commit -m x'   commit "a delimiter keeps its punctuation (#62)"
yes $'cat <<EOF-1\nbody\nEOF-1\ngit commit -m x' commit "a delimiter keeps a dash and digit (#62)"
yes $'cat <<EOF \\\n  > /dev/null\nbody\nEOF\ngit commit -m x'                commit "a heredoc body starts after its joined line"
yes $'read -r b <<<"$PWD"\ngit commit -m x'                                    commit "a here-string opens no heredoc"
yes $'echo \'x\nread -r b <<<"$PWD"\ngit commit -m x'                          commit "a here-string, split on its own, opens none (#61)"
yes $'echo \'x\ngit <<<y commit -m x'                                          commit "a here-string's word, split on its own (#152)"

# What the per-line split sees still counts, so a quote the carried split misreads hides nothing.
yes $'bash -c \'\ncd /tmp\ngit commit -m x\n\''       commit "a commit only the per-line split sees"
yes $'x=a; echo "${x#"\'"}"\ngit commit -m x\n# \''     commit "a commit after misread nested quotes"
yes $'echo \'a\ngit <<<x commit -m y\n\''                commit "the per-line split's lines read by its own here-string rule"
yes $'cat <<E\\OF\nE\neval \'echo $(git commit -m x)\'\nEOF'      commit "a payload the per-line split sees is split both ways"
cwd $'x=a; echo "${x#"\'"}"\ncd /evil\n# \'\ngit commit -m x' commit /start $'/start\n/evil' \
  "both directories when the splits disagree"
# Backticks end where the shell ends them, so quotes inside them no longer split the two apart (#87).
cwd $'echo "`echo \'"\'`"\ncd /evil\n# \'\ngit commit -m x' commit /start /evil "backticks read as the shell reads them"

# A commit after a switch to a branch, in one && chain, lands on that branch, so a guard judges it there (#81). Anything
# that may leave HEAD elsewhere first, or a link other than &&, leaves HEAD's branch to judge, as before.
targets() { OUT="$(_guardrails_git_targets "$1" commit /s)"; assert_eq "$OUT" "$2" "$3"; }
targets 'git switch -c fix/x && git commit -am x'                 'local:fix/x /s' "a commit after the branch it creates"
targets 'git checkout -b fix/x && git commit -am x'               'local:fix/x /s' "the checkout -b form"
targets 'git checkout -B fix/x origin/main && git commit -am x'   'local:fix/x /s' "checkout -B from a start point"
targets 'git switch -c fix/x && git add -A && git commit -m x'    'local:fix/x /s' "a git add between"
targets 'git switch -c x && make && git commit -m y'              'local:x /s'     "another command between"
targets 'git switch main && git commit -m x'                      'local:main /s'  "a switch to an existing branch"
targets 'git switch -c fix/x; git commit -m x'                    'local: /s'      "a ; does not carry the switch"
targets 'git switch -c fix/x || git commit -m x'                  'local: /s'      "a || does not carry the switch"
targets 'git switch -c x && true; git commit -m y'                'local: /s'      "a ; later in the chain ends it"
targets 'true || git switch -c fix/x && git commit -m x'          'local: /s'      "a switch after || may not run"
targets 'git switch -c fix/x | cat && git commit -m x'            'local: /s'      "a piped switch's status is not the chain's"
targets 'git checkout fix/x && git commit -m x'                   'local: /s'      "checkout without -b may restore a file"
targets 'git switch - && git commit -m x'                         'local: /s'      "the previous branch is not known"
targets 'git switch --detach v1 && git commit -m x'               'local: /s'      "a detached HEAD"
targets 'git switch -c a && git switch main && git commit -m x'   'local:main /s'  "the last switch counts"
targets 'git switch -c a && git checkout x && git commit -m y'    'local: /s'      "an unknown switch after a known one"
targets 'git switch -c x && git rebase main y && git commit -m z' 'local: /s'      "a rebase may switch"
targets 'git -C /a switch -c x && git commit -m y'                'local: /s'      "a switch in another repo"
targets 'git -C /a switch -c x && git -C /a commit -m y'          'local:x /a'     "a switch and a commit in the same other repo"
targets 'git switch -c x && cd sub && git commit -m y'            'local: /s/sub'  "a commit in another directory after a cd"
targets 'git switch -c x && bash -c "git switch main" && git commit -m y' 'local: /s' "a payload between may switch"
targets 'git switch -c x && git commit -m "$(git switch main)"'   'local: /s'      "a switch in a substitution"
targets 'sudo git switch -c x && git commit -m y'                 'local: /s'      "a wrapped switch"
targets 'ssh h git switch -c x && git commit -m y'                'local: /s'      "a switch on another host"
targets 'git switch -c "fix/x" && git commit -m y'                'local:fix/x /s' "a quoted branch name"
targets 'git switch --create=fix/x && git commit -m y'            'local:fix/x /s' "--create= with its name"
targets 'git switch -cfix/x && git commit -m y'                   'local:fix/x /s' "-c with its name fused"
targets 'git switch -c x && git commit -m a && git commit -m b'   'local:x /s'     "each commit in the chain"
targets $'git checkout -b x && git commit -m "$(cat <<\'EOF\'\nmsg\nEOF\n)"' 'local:x /s' "a message from a heredoc"
# The per-line split cannot see the && the switch needs; where it reads a commit the carried split does not, it is judged.
targets $'git switch -c x && git commit -m "a\ngit commit b"'     $'local:x /s\nlocal: /s' "a commit read only line by line"

# A heredoc fed to a shell is the script it runs (#63).
yes $'bash <<EOF\ngit commit -m x\nEOF'           commit "a heredoc fed to bash"
no  $'cat <<EOF\ngit commit -m x\nEOF'            commit "a heredoc fed to cat is data"
yes $'bash <<A; cat <<B\ngit commit -m x\nA\nhi\nB' commit "a shell's heredoc before another on its line (#108)"
yes $'<<EOF bash\ngit commit -m x\nEOF'           commit "a heredoc opened before the shell it feeds (#132)"
yes $'cat <<EOF `true\ngit commit -m x\n`\nbody\nEOF' commit "a backtick spanning lines after an opener runs first"
yes $'bash -c \'source /dev/stdin\' <<EOF\ngit commit -m x\nEOF' commit "a heredoc fed to a shell that also has -c (#93)"
yes $'bash script.sh <<EOF\ngit commit -m x\nEOF'  commit "a heredoc fed to a shell that also has a script file (#93)"

# Each command of a pipeline but the last runs in a subshell, so its cd does not last (#115). zsh runs the last in the
# current shell, so a cd there is followed, as before.
walk 'cd /x | git commit -m y'                    commit /s 'local: /s'  "a cd piped into the commit"
walk 'cd /x |& git commit -m y'                   commit /s 'local: /s'  "a cd piped into the commit with |&"
walk 'cd /x | cat; git commit -m y'               commit /s 'local: /s'  "a cd piped into another command"
walk 'true | cd /x | cat; git commit -m y'        commit /s 'local: /s'  "a cd in the middle of a pipeline"
walk 'echo | cd /x; git commit -m y'              commit /s 'local: /x'  "a cd at the end of a pipeline"
walk 'x=$(cd /x | true; git commit -m y)'         commit /s 'local: /s'  "a piped cd in a substitution"
walk "eval 'cd /x' | cat; git commit -m y"        commit /s 'local: /s'  "eval's cd in a pipeline"
walk 'cd /x $(a | b) | git commit -m y'           commit /s 'local: /s'  "a piped cd that holds a pipe in a substitution"
walk 'cd /x $(a | b); git commit -m y'            commit /s 'local: /x'  "a pipe in a cd's substitution does not pipe the cd"

# A shell's heredoc is the script that shell runs, so a cd in it ends with that shell, and it runs where its opener does.
cwd $'bash <<EOF\ncd /x\nEOF\ngit commit -m y'                commit /s /s    "a shell's heredoc's cd does not outlive it"
cwd $'bash <<EOF; cd /y\ngit commit -m x\nEOF'                commit /s /s    "a shell's heredoc runs before the command after its opener"
cwd $'cd /a && bash <<EOF\ncd b\ngit commit -m x\nEOF'         commit /s /a/b  "a cd in a shell's heredoc before its commit"
cwd $'bash <<A\nbash <<B\ncd /x\nB\ngit commit -m y\nA'       commit /s /s    "a nested heredoc's cd stays in it"
cwd $'x=$(bash <<EOF\ncd /y\ngit commit -m z\nEOF\n)'          commit /s /y    "a shell's heredoc inside a substitution"
cwd $'bash <<EOF\necho $(true && cd /x); git commit -m y\nEOF' commit /s /s    "a cd cut from a substitution in a heredoc"
# The shell expands an unquoted heredoc's substitutions before the shell it feeds starts, so they run where its opener
# stands; a quoted heredoc's are that shell's to run.
walk $'bash <<EOF\ncd /x\necho $(git commit -m y)\nEOF'     commit /s 'local: /s' "an unquoted shell heredoc's substitution runs before it"
walk $'bash <<\'EOF\'\ncd /x\necho $(git commit -m y)\nEOF' commit /s 'local: /x' "a quoted shell heredoc's substitution runs in it"

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
# A substitution runs before the command that holds it, in a child shell, so its commands are judged there (#114).
cwd 'echo $(git commit -m y); cd /feature'          commit /s /s  "a substitution's commit before a later cd"
cwd 'echo $(cd /x); echo $(git commit -m y)'         commit /s /s  "a cd in one substitution does not reach another"
cwd $'cat <<EOF; cd /y\n$(git commit -m x)\nEOF'     commit /s /s  "a heredoc body's substitution runs with the heredoc's command"
walk 'cd /a; echo `cd /b && git commit -m y`'        commit /s 'local: /b'  "a backtick's cd before its commit, after a cd before it"
walk 'echo $(cd /x && git commit -m y)'              commit /s 'local: /x'  "a cd in a substitution before its commit"
walk 'echo $(cd /x && echo $(git commit -m y))'      commit /s 'local: /x'  "a nested substitution after its parent's cd"
walk 'echo $(echo $(cd /x); git commit -m y)'        commit /s 'local: /s'  "a nested substitution's cd does not reach its parent"
walk 'cd /a; x=$(git commit -m y)'                   commit /s 'local: /a'  "a substitution after a cd"
# A line cut from inside a substitution at an operator is not a command of its own: its cd is not followed, as it would
# send the guard to a path that does not exist, such as /x), which skips the check.
walk 'echo $(true && cd /x); git commit -m y'        commit /s 'local: /s'  "a cd cut from a substitution is not followed"

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
  '2>/dev/null' '> log' 'f()' 'f ()' 'function f' 'case x in *)' 'in a)' 'coproc' 'timeout 5' 'nice -n 5' \
  'stdbuf -oL' 'doas -u r' 'setsid' 'chroot /j' '"env"' '\nohup'; do
  yes "$w git commit -m x"                 commit "seen through $w as a segment's first word"
done
# A shell run elsewhere is seen through too, and its commit is there.
for w in 'ssh -T h bash -c' 'docker exec -i c bash -c' 'kubectl exec p -- bash -c'; do
  there "$w 'git commit -m x'"             commit "seen through $w as a segment's first word"
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
there 'docker exec c git commit -m x'      commit "a commit in a container is there, not here"
cwd 'timeout 5 cd /x; git commit -m y'     commit /start /start "a cd behind a new wrapper is not followed"
cwd 'f() { cd /x; }; git commit -m y'      commit /start /start "a cd in a function body is not followed"

# env -C and sudo -D run their command in another directory (#112).
cwd 'env -C /x git commit -m y'                   commit /start /x       "env -C"
cwd 'sudo -D /x git commit -m y'                  commit /start /x       "sudo -D"
cwd 'env --chdir=/x git commit -m y'              commit /start /x       "env --chdir=/x"
cwd 'sudo --chdir /x git commit -m y'             commit /start /x       "sudo --chdir /x"
cwd 'env -iC /x git commit -m y'                  commit /start /x       "env -C in a cluster"
cwd 'env -C/x git commit -m y'                    commit /start /x       "env -C with its directory fused"
cwd 'sudo -uroot -D /x git commit -m y'           commit /start /x       "sudo -D after an option with its value fused"
cwd 'env -C a sudo -D b git -C c commit -m y'     commit /s /s/a/b/c     "each directory relative to the last"
cwd "env -C '/my dir' git commit -m y"            commit /start "/my dir" "a quoted directory with a blank"
HOME=/h cwd 'env -C ~/x git commit -m y'          commit /start /h/x     "a directory under ~"
cwd "env -C /x bash -c 'git commit -m y'"         commit /start /x       "a payload runs there"
cwd 'env -C /x true; git commit -m y'             commit /start /start   "the directory does not outlast the command"
cwd 'env -C /x cd /y; git commit -m y'            commit /start /start   "a cd it wraps is not followed"
chdirs() { local -a toks; read -r -a toks <<<"$1"; _guardrails_command_at; got="$got ${_GUARDRAILS_CMD_DIRS[*]}"; }
got=""; chdirs "$(printf 'a=1 %.0s' {1..64})env -C /x git commit"; chdirs "$(printf 'a=1 %.0s' {1..64})env -C /x git commit"
assert_eq "$got" " /x /x" "a long segment's kept lookup keeps its directory"
yes "env -C '/my dir' git commit -m y"            commit                 "a commit after a quoted directory with a blank"

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
cwd '"cd" /x; git commit -m y'             commit /start /x     "a quoted cd is followed, as the shell runs it (#150)"
cwd '"cd /x"; git commit -m y'             commit /start /start "a piece of a quoted argument is not a cd"
cwd "\"eval\" 'cd /x'; git commit -m y"      commit /start /x     "a quoted eval's cd lasts (#150)"

# A redirect or a quoted word between git and its subcommand does not hide the subcommand (#131).
yes 'git 2>/dev/null commit -m x'          commit "a commit behind a fused redirect after git"
yes 'git > log commit -m x'                commit "a commit behind a separate redirect after git"
yes 'git "commit" -m x'                    commit "a quoted subcommand"
yes "git 'com'mit -m x"                    commit "a partly quoted subcommand"
yes 'git \commit -m x'                     commit "an escaped subcommand"
yes 'git "--no-pager" 2>&1 push'           push   "a quoted global option and a redirect"
yes 'git -C >/dev/null /x commit -m y'     commit "a redirect between -C and its directory"
no  'git > commit status'                  commit "a redirect's target is not the subcommand"
no  'git "status" commit'                  commit "a quoted other subcommand"
no  'git --no-pager log'                   commit "a valueless global before another subcommand"
no  'git log > out'                        commit "a redirect after another subcommand"
cwd 'git 2>/dev/null -C /x "commit" -m y'  commit /start /x     "-C after a redirect"
cwd 'git -C >/dev/null /x commit -m y'     commit /start /x     "-C's directory after a redirect"
cwd 'git "-C" /x commit -m y'              commit /start /x     "a quoted -C"
# A directory is read as the shell reads one word: without its quotes, and whole though it holds a blank (#150).
cwd 'git -C "/x" commit -m y'              commit /start /x         "a quoted -C directory"
cwd "git -C '/my dir' commit -m y"         commit /start "/my dir"  "a quoted -C directory with a blank"
cwd 'git -C /my\ dir commit -m y'          commit /start "/my dir"  "a -C directory with an escaped blank"
cwd "git -C 'a b' -C c commit -m y"        commit /s "/s/a b/c"     "a quoted -C directory, then another"
yes "git -C '/my dir' commit -m y"         commit                   "a commit after a quoted -C directory with a blank"
yes 'git -c "user.name=a b" commit -m y'   commit                   "a commit after a quoted -c value with a blank"
cwd 'cd "/x" && git commit -m y'           commit /start /x         "a quoted cd directory"
cwd 'cd /x/"a b"/c && git commit -m y'     commit /start "/x/a b/c" "a cd directory quoted in its middle"
cwd "git -C /x/'a b' commit -m y"          commit /start "/x/a b"   "a -C directory quoted at its end"
cwd "cd '/my dir' && git commit -m y"      commit /start "/my dir"  "a quoted cd directory with a blank"
cwd 'cd "/é" && git commit -m y'           commit /start "/é"       "a quoted cd directory holding a multibyte character"
# The shell expands a leading ~ or ~/ to $HOME, outside quotes, so the gate does not skip a path it cannot find.
HOME=/h cwd 'cd ~/x && git commit -m y'    commit /start /h/x       "a cd to ~/x"
HOME=/h cwd 'cd ~ && git commit -m y'      commit /start /h         "a cd to ~"
HOME=/h cwd 'git -C ~/x commit -m y'       commit /start /h/x       "a -C directory under ~"
HOME=/h cwd "git -C ~/'a b' commit -m y"   commit /start "/h/a b"   "a quoted directory under ~"
HOME=/h cwd 'cd "~/x" && git commit -m y'  commit /start /start/~/x "a quoted ~ is not expanded"
HOME=/h cwd 'cd \~/x && git commit -m y'   commit /start /start/~/x "an escaped ~ is not expanded"
HOME=/h cwd 'cd ~u/x && git commit -m y'   commit /start /start/~u/x "another user's ~ is not guessed at"
HOME='' cwd 'cd ~/x && git commit -m y'      commit /start /start/~/x "no ~ without a HOME"
long="/$(printf 'a%.0s' {1..80})"
cwd "cd \"$long\" && git commit -m y"      commit /start "$long"    "a quoted cd directory longer than a name"
cwd 'git 2> -C commit -m y'                commit /start /start "a redirect's target is not -C"
# The split drops a heredoc's delimiter, so the word after its << is not the delimiter.
yes $'git <<EOF commit -m x\nbody\nEOF'     commit "a heredoc opened before the subcommand"
yes $'<<EOF git commit -m x\nbody\nEOF'     commit "a heredoc opened before git"
yes 'git << 2 commit -m x'                 commit "a numeric heredoc delimiter, which the split keeps"
yes '<< 2 git commit -m x'                 commit "a numeric heredoc delimiter before git"
# One piece of a quoted argument of several words is not read: the shell passes the argument whole, as main read it.
no  'git "commit -m x"'                    commit "a piece of a quoted argument is not the subcommand"
no  "git 'commit x' -m y"                  commit "a first piece of a quoted argument is not the subcommand"
no  'git commit\ x -m y'                   commit "a word an escaped blank joins to the next is not the subcommand"
yes "git co'mm'it -m x"                    commit "a word quoted in its middle is whole"

# With no command, sudo -s or -i, doas -s and chroot start a shell, which reads a heredoc as its script (#133).
yes $'sudo -s <<EOF\ngit commit -m x\nEOF'           commit "a heredoc fed to sudo -s"
yes $'chroot /srv/jail <<EOF\ngit commit -m x\nEOF'  commit "a heredoc fed to chroot"
no  $'sudo tee f <<EOF\ngit commit -m x\nEOF'        commit "a heredoc fed to sudo tee is data"

# ssh's command is read like a local one, as a shell's script on another host is (#113).
there 'ssh host git commit -m x'                      commit "a commit ssh runs on another host"
yes $'ssh host <<EOF\ngit commit -m x\nEOF'           commit "a heredoc fed to ssh with no command"
no  'ssh host git status'                             commit "ssh running another subcommand"

# su -c and script -c run a command line through a shell; runuser -u and script with a file run their words.
yes "su -c 'git commit -m x' root"                    commit "a commit su -c runs"
yes 'runuser -u me -- git commit -m x'                commit "a commit runuser -u runs"
yes "script -qc 'git commit -m x' /dev/null"          commit "a commit script -c runs"
yes 'script -q /dev/null git commit -m x'             commit "a commit script runs after its file"
cwd "su -c 'cd /x && git commit -m y' root"           commit /s /x "a cd in su -c's command"
cwd "su -c 'cd /x'; git commit -m y"                  commit /s /s "su -c's cd ends with its shell"
# A shell's script is the one word after its -c; the words after it are the script's arguments.
yes "bash -c 'git commit' a0"                         commit "a commit that ends a script with an argument after it"
yes "su -c 'git commit' root"                         commit "a commit that ends su -c's command"
yes 'sh -c "cd /x && git commit" a0 a1'               commit "a double-quoted script with arguments after it"
cwd "bash -c 'cd /x && git commit -m y' a0"           commit /s /x "a cd in a script with an argument after it"
no  "bash -c 'echo hi' git commit"                    commit "a script's arguments are not its commands"
yes $'bash -c \'echo hi\ngit commit -m x'             commit "a script whose quote never closes is read to its end"

# A command ssh, docker exec, kubectl exec or nsenter runs is read, but it runs elsewhere, so its repo is not here.
there 'kubectl exec pod -- git commit -m x'           commit "a commit kubectl exec runs"
there 'nsenter -t 1 -m git commit -m x'               commit "a commit nsenter runs in another namespace"
there 'ssh host bash -c "git commit -m x"'            commit "a commit in a shell on another host"
there "ssh host 'bash -c \"git commit -m x\"'"         commit "a commit in a shell in ssh's command"
there 'docker exec c bash -c "git commit -m x"'       commit "a commit in a shell in a container"
there 'sudo docker exec c git commit -m x'            commit "a commit in a container behind sudo"
there 'docker exec c ssh h git commit -m x'           commit "ssh from a container"
yes 'git commit -m x; ssh host git commit -m y'       commit "a commit here and one on another host"
yes 'docker exec c git commit -m x; git commit -m y'  commit "a commit in a container and one here"
no  'docker exec c git status'                        commit "a container running another subcommand"
walk 'ssh h git commit -m x'                          commit /s 'remote: /s'  "a commit on another host is remote"
walk 'docker exec c git -C /x commit -m x'            commit /s 'remote: /x'  "a commit in a container is remote"
walk $'ssh host <<EOF\ngit commit -m x\nEOF'          commit /s 'remote: /s'  "a heredoc's commit on another host is remote"
walk $'ssh host bash <<\'EOF\'\necho $(git commit -m x)\nEOF' commit /s 'remote: /s' "a quoted heredoc's substitution on another host"
walk $'ssh host bash <<EOF\necho $(git commit -m x)\nEOF'   commit /s 'local: /s'  "an unquoted heredoc's substitution is expanded here"
walk 'ssh h "echo $(git commit -m x)"'                commit /s 'local: /s' \
  "ssh's substitution is expanded here, and not read again in its command"
walk 'git commit -m x; ssh h git commit -m y'         commit /s $'local: /s\nremote: /s' "a commit here and one on another host"
cwd 'ssh h git commit -m x'                           commit /s /s            "a commit only on another host leaves the end directory"

# A redirect can follow a word with no blank between, and the shell reads the word without it (#91).
yes "bash<<<'git commit -m x'"      commit "a here-string with no blank after the shell"
yes 'git>/dev/null commit -m x'     commit "a redirect fused to git"
yes 'git> /dev/null commit -m x'    commit "an operator fused to git, its target after it"
yes 'git commit>/dev/null -m x'     commit "a redirect fused to the subcommand"
yes 'sudo> x git commit -m x'       commit "an operator fused to a wrapper, its target after it"
yes "bash -c\"\" 'git commit -m x'" commit "an empty argument fused to -c leaves the payload after it"
no  'git log>commit'                commit "a redirect's target is not the subcommand"

# A heredoc body runs indirectly through source of /dev/stdin, or eval's or a shell's -c substitution.
yes $'. /dev/stdin <<EOF\ngit commit -m x\nEOF'               commit "a heredoc dotted from /dev/stdin"
yes $'eval "$(cat <<EOF\ngit commit -m x\nEOF\n)"'             commit "a heredoc that eval runs through a substitution"
no  $'git tag -m "$(cat <<EOF\ngit commit -m x\nEOF\n)" v1'     commit "a tag message from a heredoc stays data"

# A redirect's target is one shell word, though a quote or an escaped blank in it spans several words of the split.
yes "> 'a b c' git commit -m x"                       commit "a quoted target with blanks before git"
yes 'git > "a b" commit -m x'                         commit "a quoted target with blanks before the subcommand"
yes "git>'a b' commit -m x"                           commit "a quoted target with blanks fused to git"
yes "git -C > 'a b' /x commit -m y"                   commit "a quoted target between -C and its directory"
cwd "git -C > 'a b' /x commit -m y"                   commit /start /x "-C's directory after a quoted target"
# A quote opened later in a target may close one opened before it, in a piece of a quoted argument, so it joins nothing.
yes '> out" git commit -m "x'                         commit "a quote opened inside a target joins no words"
yes 'git -c "a >out" -c "b" commit -m x'              commit "a piece of a quoted value that holds a redirect"
# A quote that does not close in its line is read as before, as the line may be one piece of a quote spanning lines.
yes $'echo \'x\n> \'y git commit -m x'                  commit "a target whose quote does not close in its line"
yes $'echo \'x\ngit>\'y commit -m x'                    commit "a fused target whose quote does not close in its line"

# A long segment's lookup is kept for the guards' later passes, per split, as the loop would find it again.
lookups() { local -a toks; read -r -a toks <<<"$1"; _guardrails_command_at; got="$got $_GUARDRAILS_CMD_AT/$_GUARDRAILS_CMD"; }
long="$(printf 'a=1 %.0s' {1..64})<<< w git commit"
got=""; lookups "$long"; lookups "$long"; _GUARDRAILS_SPLIT_PER_LINE=1 lookups "$long"; _GUARDRAILS_SPLIT_PER_LINE=1 lookups "$long"
assert_eq "$got" " 66/git 66/git 65/w 65/w" "a long segment's kept lookup is its split's own"
fused="$(printf 'sudo> x %.0s' {1..40})git -C /y commit -m x"
yes "$fused" commit "a commit behind 40 wrappers with a redirect fused to each"
cwd "$fused" commit /start /y "the same commit's directory, its lookup kept"

# The shell expands a substitution in a double-quoted script before it passes the script on, and passes an escaped one
# on to run there.
yes 'bash -c "echo \$(git commit -m x)"'               commit "an escaped substitution in a double-quoted script"
yes 'eval "echo \`git commit -m x\`"'                  commit "an escaped backtick in eval's double-quoted words"
there 'ssh h "echo \$(git commit -m x)"'               commit "an escaped substitution in ssh's command runs there"
no  "bash -c 'echo \\\$(git commit -m x)'"             commit "an escaped substitution in a single-quoted script"
no  'bash -c "echo \\\$(git commit -m x)"'             commit "an escaped backslash before an escaped substitution"
targets 'ssh h "echo $(git commit -m x)"'               'local: /s' "a substitution in ssh's command runs here only"
yes $'bash -c "echo "\' $(git commit -m x)\''         commit "a single-quoted substitution after a double-quoted piece"
targets 'bash -c "cd /x && echo \$(git commit -m x)"'   'local: /x' "an escaped substitution runs where the script stands"

# The shell that feeds an unquoted heredoc to another drops the backslash of \$ and \`, so the script runs that
# substitution itself, where it stands.
yes  $'bash <<EOF\necho \\$(git commit -m x)\nEOF'               commit "an escaped substitution in a shell's unquoted heredoc"
yes  $'bash <<EOF\necho \\`git commit -m x\\`\nEOF'              commit "escaped backticks in a shell's unquoted heredoc"
yes  $'bash <<EOF\necho "\\$(git commit -m x)"\nEOF'             commit "an escaped substitution in double quotes there"
no   $'bash <<\'EOF\'\necho \\$(git commit -m x)\nEOF'           commit "an escaped substitution in a quoted heredoc stays text"
no   $'cat <<EOF\necho \\$(git commit -m x)\nEOF'                commit "an escaped substitution in a heredoc no shell runs"
no   $'bash <<EOF\necho \'\\$(git commit -m x)\'\nEOF'           commit "an escaped substitution in single quotes there"
walk $'bash <<EOF\ncd /x\necho \\$(git commit -m x)\nEOF'   commit /s 'local: /x'  "it runs where the script stands"
walk $'ssh host bash <<EOF\necho \\$(git commit -m x)\nEOF' commit /s 'remote: /s' "and on another host, there"

# A wrapper's value or operand is one shell word, though a quote in it spans several words of the split.
yes 'sudo -p "Password please:" git commit -m x'     commit "a quoted prompt with a blank"
yes 'sudo -p"Password please:" git commit -m x'      commit "a quoted prompt attached to its option"
yes "sudo --prompt 'a b c' git commit -m x"          commit "a quoted value of a long option"
yes 'script -q "my log" git commit -m x'             commit "a quoted file before script's command"
cwd 'sudo -D"/a b" git commit -m x'                  commit /s "/a b" "a quoted directory attached to sudo -D"

# A cd in a ( ) or { } group is followed for the commands after it in the group, and not past the group's end.
targets '(cd /x && git commit -m y)'                          'local: /x'           "a cd in a subshell before its commit"
targets '(cd /x; git commit -m y)'                            'local: /x'           "a ; in a subshell"
targets '{ cd /x; git commit -m y; }'                         'local: /x'           "a cd in a brace group"
targets '(cd /x && git commit -m y); git commit -m z'         $'local: /x\nlocal: /s' "a subshell's cd ends with it"
targets '(cd /x && git commit -m y) 2>/dev/null; git commit -m z' $'local: /x\nlocal: /s' "a redirect after the group"
targets '{ cd /x; }; git commit -m y'                         'local: /s'           "a brace group's cd is followed inside it only"
targets '( (cd /x); git commit -m y )'                        'local: /s'           "a nested subshell's cd ends with it"
targets '(cd /x | cat; git commit -m y)'                      $'local: /s\nlocal: /x' \
  "a piped cd in a subshell, which the per-line split follows, as it sees no pipe, as without the subshell"
targets '(sudo cd /x; git commit -m y)'                       'local: /s'           "a wrapped cd in a subshell"
targets 'if true; then (cd /x && git commit -m y); fi'        'local: /s'           "a group after a keyword, as before"
targets '((n++)) && cd /x && git commit -m y'                  'local: /x'           "arithmetic opens no group"

# The split writes a backtick substitution as sh -c -- "…" with its text as written, so that script is read whole, and
# neither as one double-quoted word nor with its own substitutions made inert.
yes 'echo "`echo "a" && git commit -m x`"'          commit "a backtick substitution whose text holds quotes"
yes 'echo `echo $(git commit -m x)`'                 commit "a substitution inside backticks"

finish "git-cmd"
