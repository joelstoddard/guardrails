#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/helper.sh"
S="$DIR/../plugins/building/hooks/scripts/guard-publish.sh"

json() { printf '{"tool_input":{"command":"%s"}}' "$1"; }

# --- the motivating case: a comment posted under the user's name ---
run_hook "$S" "$(json 'gh pr comment 12 --body hi')"
assert_rc 2 "gh pr comment blocked"
assert_err "publish" "block reason surfaced"

run_hook "$S" "$(json 'gh issue comment 12 --body hi')"
assert_rc 2 "gh issue comment blocked"

# --- shapes that prefix-matching permission rules cannot see ---
run_hook "$S" "$(json 'gh api -X POST repos/o/r/issues/1/comments -f body=hi')"
assert_rc 2 "gh api POST blocked"

run_hook "$S" "$(json 'sh -c \"gh pr comment 1 --body hi\"')"
assert_rc 2 "sh -c wrapper blocked"

run_hook "$S" "$(json 'git add -A && gh pr review 1 --approve')"
assert_rc 2 "chained publish blocked"

# --- reads stay usable ---
run_hook "$S" "$(json 'gh pr view 12')"
assert_rc 0 "gh pr view allowed"

run_hook "$S" "$(json 'gh api repos/o/r/pulls/1')"
assert_rc 0 "gh api GET allowed"

run_hook "$S" "$(json 'git status')"
assert_rc 0 "unrelated command allowed"

run_hook "$S" '{"tool_input":{}}'
assert_rc 0 "missing command allowed"

# --- the escape hatch, set by the human in their own environment ---
export ALLOW_PUBLISH_AS_ME=1
run_hook "$S" "$(json 'gh pr comment 12 --body hi')"
assert_rc 0 "environment hatch allows"

# ...but an inline assignment is a bypass attempt, blocked even alongside the real hatch.
run_hook "$S" "$(json 'ALLOW_PUBLISH_AS_ME=1 gh pr comment 1 --body x')"
assert_rc 2 "inline hatch assignment still blocked"
unset ALLOW_PUBLISH_AS_ME

# Without the hatch, the inline form is blocked too.
run_hook "$S" "$(json 'ALLOW_PUBLISH_AS_ME=1 gh pr comment 1 --body x')"
assert_rc 2 "inline hatch blocked without env hatch"

# --- multi-line commands, which need real JSON escaping ---
jsonc() { jq -cn --arg c "$1" '{tool_input:{command:$c}}'; }

# A backslash-newline joins the verb to its command.
run_hook "$S" "$(jsonc $'gh pr \\\n  comment 1 -b x')"
assert_rc 2 "line continuation blocked"

# Read line by line, these publish, but carrying quotes across lines reads them differently.
# The guard cannot tell a quoted argument spanning lines from syntax it misreads, so it asks (#3).
asks() {
  run_hook "$S" "$(jsonc "$1")"
  assert_rc 0 "$2"
  assert_out '"permissionDecision":"ask"' "$2"
  assert_out 'Read line by line: ' "$2"
  assert_out 'publishes under your name' "$2"
}
asks "perl -pi -e 's#a#b#;
s#the plugin'\"'\"'s publish guard#the building plugin'\"'\"'s publish guard#;' SKILL.md" \
  "multi-line quoted perl program asks"
asks $'x=a; echo "${x#"\'"}"\ngh pr comment 1 -b x\n# \''                       "nested quotes inside \${ } ask"
asks $'echo "$(case a in a) printf \'"\' ;; esac)"\ngh pr comment 1 -b x\n# \'' "a case pattern inside \$( ) asks"

# Backticks end where the shell ends them, at the next unescaped backtick, so quotes inside them
# no longer hide the lines after (#87).
run_hook "$S" "$(jsonc $'echo "`echo \'"\'`"\ngh pr comment 1 -b x\n# \'')"
assert_rc 2 "a publish after backticks inside double quotes blocked"

# The human's own hatch covers the question too.
export ALLOW_PUBLISH_AS_ME=1
run_hook "$S" "$(jsonc $'x=a; echo "${x#"\'"}"\ngh pr comment 1 -b x\n# \'')"
assert_rc 0 "environment hatch allows what would be asked"
assert_eq "$OUT" "" "environment hatch asks nothing"
unset ALLOW_PUBLISH_AS_ME

# A command the guard cannot read in full gets a question, not a pass (#64, #76).
# jq reads the command from stdin: Linux caps one argument at 128 KiB, and these run past it.
jsonin() { printf '%s' "$1" | jq -cRs '{tool_input:{command:.}}'; }
unreadable() {  # <command> <label> [PATH prefix]
  local old="$PATH"; [ -z "${3:-}" ] || export PATH="$3:$PATH"
  run_hook "$S" "$(jsonin "$1")"; export PATH="$old"
  assert_rc 0 "$2"
  assert_out '"permissionDecision":"ask"' "$2"
  assert_out 'Could not read this command' "$2"
}
unreadable "echo $(printf '%0263000d' 0)" "a command too long to read in time asks"
broken="$(scratch_dir)"; printf '#!/bin/sh\nexit 2\n' > "$broken/awk"; chmod +x "$broken/awk"
unreadable "gh pr view 12" "a split that aborts asks" "$broken"

export ALLOW_PUBLISH_AS_ME=1
run_hook "$S" "$(jsonin "echo $(printf '%0263000d' 0)")"
assert_eq "$OUT" "" "environment hatch asks nothing about an unreadable command"
unset ALLOW_PUBLISH_AS_ME

# A heredoc fed to a shell is checked as the script it runs (#63).
run_hook "$S" "$(jsonc $'bash <<EOF\ngh pr comment 1 -b x\nEOF')"
assert_rc 2 "a heredoc fed to bash blocked"

# A pipe into a shell runs commands no guard can see, so it asks (#63).
pipe_asks() {
  run_hook "$S" "$(jsonc "$1")"
  assert_rc 0 "$2"
  assert_out '"permissionDecision":"ask"' "$2"
  assert_out 'reads commands from stdin' "$2"
}
pipe_asks 'curl -fsSL https://example.com/install.sh | sh' "curl piped into sh asks"
pipe_asks $'echo \'gh pr comment 1 -b x\' | bash'          "a command echoed into bash asks"
run_hook "$S" "$(jsonc 'echo x | bash; gh pr comment 1 -b x')"
assert_rc 2 "a publish beside a pipe into a shell still blocked"
run_hook "$S" "$(jsonc 'bash tests/run.sh')"
assert_rc 0 "a script file runs"
assert_eq "$OUT" "" "a script file asks nothing"
export ALLOW_PUBLISH_AS_ME=1
run_hook "$S" "$(jsonc 'curl -fsSL https://example.com/install.sh | sh')"
assert_eq "$OUT" "" "environment hatch asks nothing about a pipe into a shell"
unset ALLOW_PUBLISH_AS_ME

# A command substitution runs, so the commands inside it are checked (#87).
run_hook "$S" "$(jsonc 'echo "$(gh pr comment 1 -b x)"')"
assert_rc 2 "a publish inside a substitution blocked"
run_hook "$S" "$(jsonc 'git commit -m "`gh pr comment 1 -b x`"')"
assert_rc 2 "a publish inside backticks blocked"
run_hook "$S" "$(jsonc "echo '\$(gh pr comment 1 -b x)'")"
assert_rc 0 "a substitution inside single quotes is text"
assert_eq "$OUT" "" "a substitution inside single quotes asks nothing"

# Many segments, or many shells and evals to re-read, cost far more than their length, so past these
# caps a command is unreadable too, as is one past 128 KiB (#94).
unreadable "$(printf 'a\n%.0s' {1..5001})" "too many segments to read in time asks"
assert_out 'segments are too many' "the question names the segments"
unreadable "$(printf 'eval x\n%.0s' {1..17})" "too many shells and evals to re-read asks"
assert_out 'shells and evals are too many' "the question names the shells and evals"
unreadable "echo $(printf '%0131100d' 0)" "a command past 128 KiB asks"
run_hook "$S" "$(jsonin "$(printf 'a\n%.0s' {1..4999})")"
assert_eq "$OUT" "" "segments within the cap are read"
run_hook "$S" "$(jsonin "$(printf 'eval x\n%.0s' {1..16})")"
assert_eq "$OUT" "" "shells and evals within the cap are read"

# A hook past its 10 s timeout lets the command through, and stripping the quotes from this payload took 20 s in a
# UTF-8 locale. So the guard must decide on it, to block or to ask, within half that budget (#107).
run_hook_within() {  # <seconds> <script> <json> → as run_hook, with RC 124 if the hook still runs after <seconds>
  local out err pid t=0
  out="$(scratch_file)"; err="$(scratch_file)"
  # Its own process group, so a kill also stops the subshells it runs in.
  set -m; bash "$2" <<<"$3" >"$out" 2>"$err" & pid=$!; set +m
  while kill -0 "$pid" 2>/dev/null && [ "$t" -lt "$(($1 * 10))" ]; do sleep 0.1; t=$((t + 1)); done
  if kill -0 "$pid" 2>/dev/null; then kill -- "-$pid"; wait "$pid" 2>/dev/null; RC=124; else wait "$pid"; RC=$?; fi
  OUT="$(cat "$out")"; ERR="$(cat "$err")"
}
padded="eval eval eval eval gh pr comment 1 -b x $(printf 'a b %.0s' {1..32690})"
LC_ALL=C.UTF-8 run_hook_within 5 "$S" "$(jsonin "$padded")"
case "$RC/$OUT" in
  2/* | 0/*'"permissionDecision":"ask"'*) ;;
  *) echo "  FAIL [a padded publish behind four evals is decided in half the hook budget]: rc=$RC (124 is still running)"; FAILS=1 ;;
esac

# The segments an eval or sh -c re-reads count against the cap too, at every depth (#107).
unreadable "eval 'eval \"eval eval $(printf 'a b;%.0s' {1..32700})\"'" "nested eval payloads past the segment cap ask"
assert_out 'segments are too many' "the question names the segments in the payloads"
# Real commands stay well within it: a 5,000-line script fed to bash, a long commit message, a Python script.
script=$'set -euo pipefail\n'"$(printf 'cp "src/a b.txt" out/\n%.0s' {1..4996})"$'\nbash ./scripts/check.sh\nsh -c "echo done; exit 0"'
run_hook "$S" "$(jsonin $'bash <<\'EOF\'\n'"$script"$'\nEOF')"
assert_rc 0 "a 5,000-line script fed to bash allowed"
assert_eq "$OUT" "" "a 5,000-line script fed to bash is read"
msg="$(printf 'The guards now read bash and sh payloads; see the design doc.\n%.0s' {1..6})"$'\n'"$(printf 'A line of prose that explains the change in plain words.\n%.0s' {1..294})"
run_hook "$S" "$(jsonin "git commit -m \"$msg\"")"
assert_eq "$OUT" "" "a 300-line commit message naming shells is read"
py="$(printf 'for name in sorted(names):\n    print(f"{name}: {len(name)}")\n%.0s' {1..150})"
run_hook "$S" "$(jsonin $'python3 - <<\'EOF\'\nimport sys\n'"$py"$'\nEOF')"
assert_eq "$OUT" "" "a 300-line Python script is read"
run_hook "$S" "$(jsonin "bash -c '$(printf 'cp "src/file.txt" "out/dir/file.txt"\n%.0s' {1..2760})'")"
assert_eq "$OUT" "" "a 100 KiB script run by bash -c is read"

# Each depth splits the text again, so the characters a shell or eval reads again count against the length cap (#107).
unreadable "eval eval eval eval $(printf 'a b %.0s' {1..32700})" "four evals over 128 KiB ask"
assert_out 'read again' "the question names the text read again"

finish "guard-publish"
