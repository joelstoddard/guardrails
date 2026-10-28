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
# The refusal names the step to take, not a skill that ships in no plugin (#80).
assert_err "Create a branch first" "block names the step"
case "$ERR" in *start-ticket*) echo "  FAIL [block names no missing skill]: $ERR"; FAILS=1 ;; esac

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
# The cap counts bytes, as a UTF-8 locale would count these as 33,016 characters (#151).
wide="git commit -m $(printf '\360\237\230\200%.0s' {1..33000})"
LC_ALL=C.UTF-8 run_hook "$S" "$(printf '%s' "$wide" | jq -cRs --arg cwd "$r12" '{cwd:$cwd,tool_input:{command:.}}')"
assert_out '"permissionDecision":"ask"' "four-byte characters past 128 KiB ask"
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
# A shell with -c can still run its heredoc, so the body stays a script (#93).
run_hook "$S" "$(jq -cn --arg cwd "$r13" --arg c $'bash -c \'source /dev/stdin\' <<EOF\ngit commit -m x\nEOF' '{cwd:$cwd,tool_input:{command:$c}}')"
assert_rc 2 "a commit in a heredoc fed to a shell that also has -c blocked"

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
# A lone & ends a command (#89).
run_hook "$S" "$(jsonat "$r13" 'true & git commit -m x')"
assert_rc 2 "a commit after a lone & on the default branch blocked"

# An unquoted heredoc runs the substitutions in its body (#88).
run_hook "$S" "$(jsonat "$r13" $'cat <<EOF\n$(git commit -m x)\nEOF')"
assert_rc 2 "a commit in an unquoted heredoc body on the default branch blocked"

# A keyword or wrapper before git does not hide it (#90).
run_hook "$S" "$(jsonat "$r13" 'sudo git commit -m x')"
assert_rc 2 "a commit behind sudo on the default branch blocked"
run_hook "$S" "$(jsonat "$r13" 'if true; then git commit -m x; fi')"
assert_rc 2 "a commit after then on the default branch blocked"
run_hook "$S" "$(jsonat "$r13" 'env FOO=1 git status')"
assert_rc 0 "env FOO=1 git status allowed"
assert_eq "$OUT" "" "env FOO=1 git status asks nothing"
# A subshell's cd does not last, so the commit after it lands where the shell sits.
run_hook "$S" "$(jsonat "$r13" "(cd $r14b); git commit -m x")"
assert_rc 2 "a commit after a subshell's cd on the default branch blocked"

# A redirect before git is not the command (#109).
run_hook "$S" "$(jsonat "$r13" '2>/dev/null git commit -m x')"
assert_rc 2 "a commit behind a redirect on the default branch blocked"

# A function body, a case arm or a coproc runs its command, as does a command behind more wrappers (#110).
run_hook "$S" "$(jsonat "$r13" 'f() { git commit -m x; }; f')"
assert_rc 2 "a commit in a function body on the default branch blocked"
run_hook "$S" "$(jsonat "$r13" 'timeout 30 git commit -m x')"
assert_rc 2 "a commit behind timeout on the default branch blocked"

# A wrapper's long option can take the next word as its value (#116).
run_hook "$S" "$(jsonat "$r13" 'sudo --user root git commit -m x')"
assert_rc 2 "a commit behind sudo --user on the default branch blocked"

# A quoted or escaped command word is read as itself (#111).
run_hook "$S" "$(jsonat "$r13" '"git" commit -m x')"
assert_rc 2 "a commit by a quoted git on the default branch blocked"

# A redirect or a quoted word between git and its subcommand does not hide it (#131).
run_hook "$S" "$(jsonat "$r13" 'git 2>/dev/null commit -m x')"
assert_rc 2 "a commit behind a redirect after git on the default branch blocked"
run_hook "$S" "$(jsonat "$r13" 'git "commit" -m x')"
assert_rc 2 "a quoted commit on the default branch blocked"
run_hook "$S" "$(jsonat "$r14b" "git 2>/dev/null -C $r13 commit -m x")"
assert_rc 2 "a commit -C into a default-branch repo after a redirect blocked"
run_hook "$S" "$(jsonat "$r2" 'git commit -m "x"')"
assert_rc 0 "a commit with a quoted message on a feature branch allowed"
for c in 'git -C /x status' 'git --no-pager log' 'git log > out'; do
  run_hook "$S" "$(jsonat "$r13" "$c")"
  assert_rc 0 "$c allowed on the default branch"
  assert_eq "$OUT" "" "$c asks nothing"
done

# A shell's name with quotes inside it is still its name (#134).
run_hook "$S" "$(jsonat "$r13" 'cat cmds.txt | b"as"h')"
assert_out '"permissionDecision":"ask"' "a pipe into a shell whose name holds quotes asks on a default branch"

# One piece of a quoted argument is not read as the subcommand, as on main (#131).
run_hook "$S" "$(jsonat "$r13" 'git "commit -m x"')"
assert_rc 0 "a piece of a quoted argument is not a commit on the default branch"
assert_eq "$OUT" "" "a piece of a quoted argument asks nothing"

# A line split on its own reads a here-string as the shell does, so the lines after it are not lost (#61, #152).
run_hook "$S" "$(jsonat "$r13" $'echo \'x\nread -r b <<<"$PWD"\ngit commit -m x')"
assert_rc 2 "a commit after a here-string, split on its own, on the default branch blocked"

# The per-line split's lines are read by its own rule, which takes no word after a here-string, as it drops that word.
run_hook "$S" "$(jsonat "$r13" $'echo \'a\ngit <<<x commit -m y\n\'')"
assert_rc 2 "a commit the per-line split sees past a here-string on the default branch blocked"

# A heredoc's delimiter is read as the shell reads it, so <<E\OF ends at EOF and the commit after it is seen (#62).
run_hook "$S" "$(jsonat "$r13" $'cat <<E\\OF\nbody\nEOF\ngit commit -m x')"
assert_rc 2 "a commit after a heredoc whose delimiter holds a backslash on the default branch blocked"

# Each heredoc a line opens has its body read in turn, by its own rule (#108).
run_hook "$S" "$(jsonat "$r13" $'bash <<A; cat <<B\ngit commit -m x\nA\nhi\nB')"
assert_rc 2 "a commit in a shell's heredoc before another on its line on the default branch blocked"

# A shell's name after a heredoc opener makes it a script too (#132).
run_hook "$S" "$(jsonat "$r13" $'<<EOF bash\ngit commit -m x\nEOF')"
assert_rc 2 "a commit in a heredoc opened before the shell it feeds on the default branch blocked"

# A body starts once the command that opened it ends, after a backtick it spans, which runs first.
run_hook "$S" "$(jsonat "$r13" $'cat <<EOF `true\ngit commit -m x\n`\nbody\nEOF')"
assert_rc 2 "a commit in a backtick spanning lines after an opener on the default branch blocked"

# A redirect can follow a word with no blank between, and the shell reads the word without it (#91).
run_hook "$S" "$(jsonat "$r13" 'git>/dev/null commit -m x')"
assert_rc 2 "a commit by git with a redirect fused to it on the default branch blocked"
run_hook "$S" "$(jsonat "$r13" 'git commit>/dev/null -m x')"
assert_rc 2 "a commit with a redirect fused to the subcommand on the default branch blocked (#147)"

# With no command, chroot starts a shell, which reads commands from stdin (#133).
run_hook "$S" "$(jsonat "$r13" 'cat cmds.txt | chroot /srv/jail')"
assert_out '"permissionDecision":"ask"' "a pipe into chroot asks on a default branch"
assert_out 'reads commands from stdin' "the question says why for chroot"

# A pipe into ssh with no command feeds a shell there, which could commit unseen (#113).
run_hook "$S" "$(jsonat "$r13" 'cat cmds.txt | ssh host')"
assert_out '"permissionDecision":"ask"' "a pipe into ssh with no command asks on a default branch"

# A pipe into another interpreter could commit unseen (#92).
run_hook "$S" "$(jsonat "$r13" 'cat cmds.txt | node')"
assert_out '"permissionDecision":"ask"' "a pipe into node asks on a default branch"
run_hook "$S" "$(jsonat "$r13" "echo '{}' | python3 -m json.tool")"
assert_eq "$OUT" "" "a pipe into a python module asks nothing on a default branch"

# A script nested past the four depths the guards read could commit unseen (#102).
run_hook "$S" "$(jsonat "$r13" 'eval eval eval eval eval git commit -m x')"
assert_out '"permissionDecision":"ask"' "a commit five evals deep asks on a default branch"
assert_out 'more than four shells or evals deep' "the question names the depth"
run_hook "$S" "$(jsonat "$r2" 'eval eval eval eval eval git commit -m x')"
assert_eq "$OUT" "" "a commit five evals deep asks nothing off the default branch"

# A heredoc body runs indirectly through eval's substitution, but a commit message from one is data.
run_hook "$S" "$(jsonat "$r13" $'eval "$(cat <<EOF\ngit commit -m x\nEOF\n)"')"
assert_rc 2 "a commit in a heredoc that eval runs on the default branch blocked"
run_hook "$S" "$(jsonat "$r2" $'git commit -m "$(cat <<EOF\ngit commit is prose\nEOF\n)"')"
assert_rc 0 "a commit whose message comes from a heredoc allowed on a feature branch"
assert_eq "$OUT" "" "a commit whose message comes from a heredoc asks nothing on a feature branch"

# A redirect's target is one shell word, though a quote in it spans several words of the split.
run_hook "$S" "$(jsonat "$r13" "> 'a b c' git commit -m x")"
assert_rc 2 "a commit after a quoted target with blanks on the default branch blocked"

# A quoted directory is read without its quotes, as the shell passes it, so it does not resolve to a path that does not
# exist and slip past the guard (#150).
run_hook "$S" "$(jsonat "$r2" "git -C \"$r13\" commit -m x")"
assert_rc 2 "a commit -C into a quoted default-branch directory blocked"
run_hook "$S" "$(jsonat "$r2" "cd '$r13' && git commit -m x")"
assert_rc 2 "a cd into a quoted default-branch directory then commit blocked"
HOME="$(dirname "$r13")" run_hook "$S" "$(jsonat "$r2" "cd ~/$(basename "$r13") && git commit -m x")"
assert_rc 2 "a cd under ~ into a default-branch repo then commit blocked"

# env -C and sudo -D run their command in another directory (#112).
run_hook "$S" "$(jsonat "$r2" "env -C $r13 git commit -m x")"
assert_rc 2 "a commit behind env -C into a default-branch repo blocked"

# A substitution's commit is judged where it runs, before a cd after it, and a cd cut from inside one is not followed
# to a path that does not exist (#114).
run_hook "$S" "$(jsonat "$r13" "echo \$(git commit -m x); cd $r2")"
assert_rc 2 "a substitution's commit on the default branch before a cd blocked"
run_hook "$S" "$(jsonat "$r13" "echo \$(true && cd $r2); git commit -m x")"
assert_rc 2 "a commit after a cd inside a substitution on the default branch blocked"

# A shell's heredoc runs with the command that opened it, before a cd after that on its line.
run_hook "$S" "$(jsonat "$r13" $'bash <<EOF; cd '"$r2"$'\ngit commit -m x\nEOF')"
assert_rc 2 "a commit on the default branch in a shell's heredoc before a cd blocked"

# A cd piped into the commit runs in a subshell, so the commit lands where the shell sits (#115).
run_hook "$S" "$(jsonat "$r13" "cd $r2 | git commit -m x")"
assert_rc 2 "a commit on the default branch after a piped cd blocked"

# Every commit is judged, not only the first.
run_hook "$S" "$(jsonat "$r2" "git commit -m x && git -C $r13 commit -m y")"
assert_rc 2 "a second commit, on a default branch, blocked"
# Each directory costs git calls, so past 64 the guard cannot judge them all in time and asks.
many="$(for i in $(seq 65); do printf 'git -C /nonexistent/%s commit -m x; ' "$i"; done)"
run_hook "$S" "$(jsonat "$r2" "$many")"
assert_out '"permissionDecision":"ask"' "commits in 65 directories ask"
assert_out 'more than 64 directories' "the question names the directories"
run_hook "$S" "$(jsonat "$r2" "${many%git -C /nonexistent/65 *}")"
assert_eq "$OUT" "" "commits in 64 directories ask nothing"

# A library that does not load checks nothing, so the guard asks rather than allows.
# broken_hook <library> <how> → the path of a copy of the hook whose library is broken that way: a syntax error at its
# end or in its middle, or the file missing.
broken_hook() {
  local d lib; d="$(scratch_dir)"; mkdir -p "$d/hooks/scripts" "$d/lib"
  cp "$S" "$d/hooks/scripts/"; cp "$DIR/../plugins/building/lib/"*.sh "$d/lib/"
  lib="$d/lib/$1"
  case "$2" in
    end) printf 'f() {\n' >>"$lib" ;;
    middle) awk 'NR == 20 { print "if then fi" } { print }' "$lib" >"$lib.x" && mv "$lib.x" "$lib" ;;
    missing) rm "$lib" ;;
  esac
  printf '%s' "$d/hooks/scripts/${S##*/}"
}
# The hook's own library breaks in its middle, shell-split.sh at its end or by going missing.
for how in end middle missing; do
  lib=shell-split.sh; [ "$how" != middle ] || lib=git-cmd.sh
  run_hook "$(broken_hook "$lib" "$how")" "$(jsonat "$r2" 'git status')"
  assert_rc 0 "a hook whose library is broken ($how) is not refused outright"
  assert_out '"permissionDecision":"ask"' "a hook whose library is broken ($how) asks"
  assert_out 'Could not load' "the question says the library did not load ($how)"
done
# The hook itself asks too, where a function in its environment shadows the . that sources its library and fails, or
# loads nothing. The copies above break real files; this runs the hook the coverage floor measures.
for dot in 'return 1' ':'; do
  OUT="$(.() { $dot; }; export -f .; printf '%s' "$(jsonat "$r2" 'git status')" | bash "$S" 2>/dev/null)"
  assert_out 'Could not load' "the hook asks when its . does $dot"
done
export ALLOW_DEFAULT_COMMIT=1
run_hook "$(broken_hook shell-split.sh missing)" "$(jsonat "$r2" 'git status')"
assert_eq "$OUT" "" "the override asks nothing about a library that did not load"
unset ALLOW_DEFAULT_COMMIT

finish "guard-default-branch"
