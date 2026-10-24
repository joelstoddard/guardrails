#!/usr/bin/env bash
# Tests tests/mutate.sh against small fixture repos. See docs/design/coverage.md
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/helper.sh"
TOOL="$DIR/mutate.sh"
M=plugins/p/hooks/scripts/m.sh
RUNS='$(dirname "$0")/../plugins/p/hooks/scripts' # how a fixture test finds the fixture's scripts

fail() { echo "  FAIL [$1]: $2"; FAILS=1; }

setup() { # → a fixture repo in $D: m.sh has a caught mutant, a missed one and an uncovered branch
  D="$(scratch_dir)"; mkdir -p "$D/plugins/p/hooks/scripts" "$D/tests"
  cat >"$D/$M" <<'EOF'
# fixture
if [[ ${1:-} == yes ]]; then
  echo "took yes"
else
  echo "took no"
fi
echo "side note" >/dev/null
EOF
  printf '%s\n' "[[ \$(bash \"$RUNS/m.sh\" yes) == \"took yes\" ]]" >"$D/tests/test_m.sh"
  floors "$M" 66.6 TOTAL 66.6
}
floors() { # path percent [path percent...] → the fixture's mutation floor file
  : >"$D/tests/mutation-floor.tsv"
  while (($#)); do printf '%s\t%s\n' "$1" "$2" >>"$D/tests/mutation-floor.tsv"; shift 2; done
}
fixture() { # <name> <script> <test>: a measured script and its test, with a 100.0 floor for a run of that file
  printf '%s\n' "$2" >"$D/plugins/p/hooks/scripts/$1.sh"
  printf '%s\n' "$3" >"$D/tests/test_$1.sh"
  floors "plugins/p/hooks/scripts/$1.sh" 100.0
}
mut() { OUTPUT="$(COV_LOG='' COVERAGE_ROOT="$D" bash "$TOOL" "$@" 2>&1)"; RC=$?; }
row() { printf '%s\n' "$OUTPUT" | awk -v f="$1" '$NF == f { print $1, $2 }'; } # → "killed/scored score"
verdict() { # → "floor status": the floor, then ok, LOW, NO FLOOR or BAD
  printf '%s\n' "$OUTPUT" | awk -v f="$1" '$NF == f { $NF = $1 = $2 = $4 = ""; gsub(/ +/, " "); sub(/^ /, ""); sub(/ $/, ""); print }'
}
most() { printf '%s\n' "$OUTPUT" | awk -v f="$1" '$NF == f { print $4 }'; } # → the row's ceiling on survivors
status_of() { awk -F'\t' -v l="$1" -v o="$2" '$3 == l && $4 == o { print $1 }' "$D/.coverage/mutants.tsv"; }
mutants() { cat "$D/.coverage/mutants.tsv" 2>/dev/null; }
hang_fixture() { # → $H: a script whose `false` mutant hangs its test; the clean test takes 0.5s, so the hang limit is about 5s
  H=hang_$RANDOM$RANDOM
  fixture "$H" $'while false; do :; done\necho looped' "sleep 0.5; [[ \$(bash \"$RUNS/$H.sh\") == looped ]]"
}
start_hung_run() { # → $RUN: a run of $H.sh in its own process group, with the hung test in flight
  COV_LOG='' COVERAGE_ROOT="$D" perl -e 'setpgrp(0, 0); $SIG{INT} = "DEFAULT"; exec @ARGV' \
    bash "$TOOL" "plugins/p/hooks/scripts/$H.sh" >/dev/null 2>&1 &
  RUN=$!
  local in_test="/hooks/scripts/$H.sh" i # the test's own process, not the run's command line
  for ((i = 0; i < 100; i++)); do # in flight = still there after 0.3s; the unmutated runs exit in milliseconds
    if [[ -n $(running "$in_test") ]]; then sleep 0.3; [[ -n $(running "$in_test") ]] && break; fi
    sleep 0.1
  done
  [[ -n $(running "$in_test") ]] || fail start "the hung test never started"
}
# In a UTF-8 locale pgrep fails on any process whose command line holds invalid bytes, which read as none running.
running() { LC_ALL=C pgrep -f "$1"; }
gone() { # <pattern>: waits up to 2s for no process to match; fails and kills them if some still do
  local i
  for ((i = 0; i < 20; i++)); do running "$1" >/dev/null; (($? == 1)) && return 0; sleep 0.1; done
  fail "$2" "still running: $(LC_ALL=C pgrep -fl "$1")"; LC_ALL=C pkill -9 -f "$1"
}

# On a bash older than 5 every case below would fail, so stop with the tool's reason.
why="$(bash "$TOOL" -j 0 2>&1)"
[[ $why == *"-j needs a positive number"* ]] || { fail "the bash on PATH runs the tool" "$why"; finish "mutate-tools"; }

echo "--- a mutant a test catches is killed, and one it misses survives"
setup; mut
[[ $RC == 0 && $(row "$M") == "2/3 66.6" ]] || fail score "rc=$RC: $OUTPUT"
[[ $(status_of 2 '==') == killed && $(status_of 3 delete) == killed ]] || fail killed "$(mutants)"
[[ $OUTPUT == *"survived  $M:7  delete  echo \"side note\" >/dev/null  ->  :"* ]] || fail survivor "$OUTPUT"

echo "--- a mutant keeps the backslashes of its line exactly"
setup
fixture e $'v=\'a\\nb\'; [[ ${#v} == 4 ]] && echo four' "[[ \$(bash \"$RUNS/e.sh\") == four ]]"
mut plugins/p/hooks/scripts/e.sh
[[ $(status_of 1 '==') == killed && $(status_of 1 '&&') == killed ]] || fail backslash "$(mutants)"

echo "--- an uncovered line gets no mutants"
setup; mut
[[ -z $(awk -F'\t' '$3 == 5' "$D/.coverage/mutants.tsv") ]] || fail uncovered "$(mutants)"

echo "--- an ignore entry with a reason takes its mutant out of the score"
setup
printf '%s\tdelete\techo "side note" >/dev/null\toutput goes to /dev/null\n' "$M" >"$D/tests/mutants-ignore.tsv"
mut
[[ $RC == 0 && $(row "$M") == "2/2 100.0" && $OUTPUT != *survived* ]] || fail ignored "rc=$RC: $OUTPUT"
[[ $(status_of 7 delete) == ignored ]] || fail ignored-status "$(mutants)"

echo "--- an ignore entry without a reason is refused"
setup; printf '%s\tdelete\techo "side note" >/dev/null\t\n' "$M" >"$D/tests/mutants-ignore.tsv"; mut
[[ $RC == 2 && $OUTPUT == *"has no reason"* ]] || fail no-reason "rc=$RC: $OUTPUT"

echo "--- a mutant that makes a test hang counts as killed, and leaves no process behind"
setup; hang_fixture
mut "plugins/p/hooks/scripts/$H.sh"
[[ $(status_of 1 false) == killed && $(row "plugins/p/hooks/scripts/$H.sh") == "2/2 100.0" ]] || fail hang "rc=$RC: $OUTPUT"
gone "$H.sh" orphan
[[ $OUTPUT != *"Alarm clock"* ]] || fail alarm-noise "$OUTPUT"

echo "--- killing the run takes a hung test with it"
setup; hang_fixture
start_hung_run
kill -TERM -- "-$RUN"; wait "$RUN" 2>/dev/null
gone "$H.sh" term-orphan # the wrapper can kill the group after the run has exited

echo "--- interrupting the run takes its workers and their hung test with it"
setup; hang_fixture
start_hung_run
kill -INT "$RUN"; wait "$RUN" 2>/dev/null # the main shell only: a worker ignores INT, and INT to the group would also end the test wrappers
gone "$H.sh" int-workers # within 2s; the hang limit is about 5s

echo "--- a test that exits leaving a background process behind leaves nothing running"
setup; B=bg_$RANDOM$RANDOM; N=$((100000 + RANDOM))
fixture "$B" "if [[ \${1:-} == go ]]; then echo done; else sleep $N >/dev/null 2>&1 & echo done; fi" \
  "[[ \$(bash \"$RUNS/$B.sh\" go) == done ]]"
floors "plugins/p/hooks/scripts/$B.sh" 50.0
mut "plugins/p/hooks/scripts/$B.sh"
[[ $(status_of 1 '==') == survived ]] || fail bg-start "rc=$RC: $OUTPUT"
gone "sleep $N" bg-orphan

echo "--- a mutant that does not parse is invalid and out of the score"
setup
fixture i $'echo one; echo "a\nb"' "[[ \$(bash \"$RUNS/i.sh\") == \$'one\\na\\nb' ]]"
mut plugins/p/hooks/scripts/i.sh
[[ $(status_of 1 delete) == invalid && $(row plugins/p/hooks/scripts/i.sh) == "0/0 100.0" ]] || fail invalid "rc=$RC: $OUTPUT"

echo "--- a measured file that does not parse stops the run"
setup; echo 'echo "unterminated' >"$D/plugins/p/hooks/scripts/bad.sh"; mut
[[ $RC == 1 && $OUTPUT == *"plugins/p/hooks/scripts/bad.sh does not parse"* ]] || fail unparsable "rc=$RC: $OUTPUT"

echo "--- a measured file whose tests did not run stops the run"
setup; fixture s 'echo s' 'exit 0'; mut plugins/p/hooks/scripts/s.sh
[[ $RC == 1 && $OUTPUT == *"plugins/p/hooks/scripts/s.sh has no covered line"* ]] || fail uncovered-file "rc=$RC: $OUTPUT"

echo "--- a failing suite stops the run before any mutant"
setup; echo 'exit 1' >"$D/tests/test_broken.sh"; mut
[[ $RC == 1 && $OUTPUT == *"suites fail"* && ! -e $D/.coverage/mutants.tsv ]] || fail red "rc=$RC: $OUTPUT"

echo "--- a file outside the measured set is refused"
setup; mut plugins/nope.sh
[[ $RC == 2 && $OUTPUT == *"not a measured file"* ]] || fail unmeasured "rc=$RC: $OUTPUT"

echo "--- a test wrapper that fails by itself (exit 127 or 255) fails the run, and no mutant counts as killed"
for code in 127 255; do
  setup; mkdir "$D/bin"
  cat >"$D/bin/perl" <<EOF
#!/usr/bin/env bash
n=\$(( \$(cat "$D/calls" 2>/dev/null || echo 0) + 1 )); echo \$n > "$D/calls"
((n <= 1)) && exec $(command -v perl) "\$@"
exit $code
EOF
  chmod +x "$D/bin/perl"
  OUTPUT="$(PATH="$D/bin:$PATH" COV_LOG='' COVERAGE_ROOT="$D" bash "$TOOL" -j 1 2>&1)"; RC=$?
  [[ $RC == 1 && $OUTPUT == *"a mutation worker failed"* ]] || fail "wrapper-$code" "rc=$RC: $OUTPUT"
  [[ $(cat "$D/calls") -ge 2 && ! -e $D/.coverage/mutants.tsv ]] || fail "wrapper-$code-scored" "calls=$(cat "$D/calls"): $OUTPUT"
done

echo "--- a file named twice is mutated once"
setup; mut "$M" "$M"
[[ $RC == 0 && $(row "$M") == "2/3 66.6" && $(printf '%s\n' "$OUTPUT" | grep -c 'm\.sh$') == 1 && $OUTPUT != *TOTAL* ]] ||
  fail twice "rc=$RC: $OUTPUT"

echo "--- --changed mutates only the measured files changed since main, or since the revision it is given"
setup; fixture g 'echo g' "[[ \$(bash \"$RUNS/g.sh\") == g ]]"
git -C "$D" init -q && git -C "$D" add -A && git -C "$D" -c user.email=t@t -c user.name=t commit -qm seed &&
  git -C "$D" update-ref refs/remotes/origin/main HEAD
echo '# changed' >>"$D/plugins/p/hooks/scripts/g.sh"
floors plugins/p/hooks/scripts/g.sh 100.0
mut --changed
[[ $RC == 0 && -n $(row plugins/p/hooks/scripts/g.sh) && -z $(row "$M") ]] || fail changed "rc=$RC: $OUTPUT"
git -C "$D" update-ref -d refs/remotes/origin/main
mut --changed HEAD
[[ $RC == 0 && -n $(row plugins/p/hooks/scripts/g.sh) && -z $(row "$M") ]] || fail changed-rev "rc=$RC: $OUTPUT"
mut --changed no-such-revision
[[ $RC == 2 && $OUTPUT == *"cannot diff against no-such-revision"* ]] || fail changed-bad-rev "rc=$RC: $OUTPUT"

echo "--- one worker and many workers give the same results"
setup; mut -j 1; one="$(mutants)"; mut -j 3
[[ $RC == 0 && $(mutants) == "$one" ]] || fail workers "differs: $(mutants)"

echo "--- a score at or above its floor is ok, survivors or not"
setup; mut
[[ $RC == 0 && $(verdict "$M") == "66.6 ok" && $(verdict TOTAL) == "66.6 ok" && $OUTPUT == *survived* ]] || fail floor-equal "rc=$RC: $OUTPUT"
floors "$M" 50.0 TOTAL 50.0; mut
[[ $RC == 0 && $(verdict "$M") == "50.0 ok" && $(verdict TOTAL) == "50.0 ok" ]] || fail floor-above "rc=$RC: $OUTPUT"

echo "--- a file below its floor is LOW and fails the run after the survivors print"
setup; floors "$M" 70.0 TOTAL 66.6; mut
[[ $RC == 1 && $(verdict "$M") == "70.0 LOW" && $(verdict TOTAL) == "66.6 ok" ]] || fail floor-low "rc=$RC: $OUTPUT"
[[ $OUTPUT == *"survived  $M:7  delete"* ]] || fail floor-low-survivors "$OUTPUT"

echo "--- a total below its floor is LOW and fails a full run"
setup; floors "$M" 66.6 TOTAL 70.0; mut
[[ $RC == 1 && $(verdict "$M") == "66.6 ok" && $(verdict TOTAL) == "70.0 LOW" ]] || fail total-low "rc=$RC: $OUTPUT"

echo "--- a scored file with no floor is NO FLOOR and fails the run"
setup; floors TOTAL 66.6; mut
[[ $RC == 1 && $(verdict "$M") == "- NO FLOOR" ]] || fail no-floor "rc=$RC: $OUTPUT"
rm "$D/tests/mutation-floor.tsv"; mut
[[ $RC == 1 && $(verdict "$M") == "- NO FLOOR" && $(verdict TOTAL) == "- NO FLOOR" ]] || fail no-floor-file "rc=$RC: $OUTPUT"

echo "--- a malformed floor is BAD and fails the run"
setup; floors "$M" abc TOTAL 66.6; mut
[[ $RC == 1 && $(verdict "$M") == "abc BAD" ]] || fail bad-floor "rc=$RC: $OUTPUT"
floors "$M" 66.6 TOTAL 66.6; printf '%s\t99.9\n' "$M" >>"$D/tests/mutation-floor.tsv"; mut
[[ $RC == 1 && $(printf '%s\n' "$OUTPUT" | grep -c ' BAD ') == 1 ]] || fail duplicate-floor "rc=$RC: $OUTPUT"

echo "--- a partial run checks only its own file, and shows and checks no total"
setup; floors "$M" 66.6 TOTAL 100.0; mut "$M"
[[ $RC == 0 && $(verdict "$M") == "66.6 ok" && $OUTPUT != *TOTAL* ]] || fail partial-ok "rc=$RC: $OUTPUT"
floors "$M" 70.0 TOTAL 100.0; mut "$M"
[[ $RC == 1 && $(verdict "$M") == "70.0 LOW" && $OUTPUT != *TOTAL* ]] || fail partial-low "rc=$RC: $OUTPUT"

echo "--- --update after a full run writes floors and raises a lower one"
setup; rm "$D/tests/mutation-floor.tsv"; mut --update
[[ $RC == 0 && $(cat "$D/tests/mutation-floor.tsv") == "$M"$'\t66.6\t1\nTOTAL\t66.6\t1' ]] || fail update-new "rc=$RC: $OUTPUT"
floors "$M" 50.0 TOTAL 50.0; mut --update
[[ $RC == 0 && $(cat "$D/tests/mutation-floor.tsv") == "$M"$'\t66.6\t1\nTOTAL\t66.6\t1' ]] ||
  fail update-raise "rc=$RC: $(cat "$D/tests/mutation-floor.tsv")"

echo "--- --update never lowers a higher floor"
setup; floors "$M" 90.0 TOTAL 90.0; mut --update
[[ $RC == 1 && $(cat "$D/tests/mutation-floor.tsv") == "$M"$'\t90.0\t1\nTOTAL\t90.0\t1' ]] ||
  fail update-keeps "rc=$RC: $(cat "$D/tests/mutation-floor.tsv")"

echo "--- deleting a line whose mutants were killed passes, though the score falls, while no survivor is added"
setup; printf '%s\t66.6\t1\nTOTAL\t66.6\t1\n' "$M" >"$D/tests/mutation-floor.tsv"
printf 'echo "took yes"\necho "side note" >/dev/null\n' >"$D/$M"; mut
[[ $RC == 0 && $(row "$M") == "1/2 50.0" && $(verdict "$M") == "66.6 ok" && $(verdict TOTAL) == "66.6 ok" ]] ||
  fail deleted-killed "rc=$RC: $OUTPUT"

echo "--- an added survivor fails a score that fell"
setup; printf '%s\t66.6\t1\nTOTAL\t66.6\t1\n' "$M" >"$D/tests/mutation-floor.tsv"
echo 'echo "another note" >/dev/null' >>"$D/$M"; mut
[[ $RC == 1 && $(row "$M") == "2/4 50.0" && $(verdict "$M") == "66.6 LOW" ]] || fail added-survivor "rc=$RC: $OUTPUT"

echo "--- --update lowers a ceiling to the survivors there are and never raises one, and a malformed ceiling is BAD"
setup; printf '%s\t66.6\t3\nTOTAL\t66.6\t3\n' "$M" >"$D/tests/mutation-floor.tsv"; mut --update
[[ $RC == 0 && $(cat "$D/tests/mutation-floor.tsv") == "$M"$'\t66.6\t1\nTOTAL\t66.6\t1' ]] || fail ceiling-lowered "rc=$RC: $OUTPUT"
printf '%s\t66.6\t0\nTOTAL\t66.6\t0\n' "$M" >"$D/tests/mutation-floor.tsv"; mut --update
[[ $(cat "$D/tests/mutation-floor.tsv") == "$M"$'\t66.6\t0\nTOTAL\t66.6\t0' && $(most "$M") == 0 ]] ||
  fail ceiling-not-raised "rc=$RC: $(cat "$D/tests/mutation-floor.tsv")"
printf '%s\t66.6\tx\nTOTAL\t66.6\t1\n' "$M" >"$D/tests/mutation-floor.tsv"; mut
[[ $RC == 1 && $(verdict "$M") == "66.6 BAD" ]] || fail ceiling-bad "rc=$RC: $OUTPUT"

echo "--- --update leaves a floor file with a malformed value untouched"
setup; floors "$M" abc TOTAL 50.0; mut --update
[[ $RC == 1 && $(cat "$D/tests/mutation-floor.tsv") == "$M"$'\tabc\nTOTAL\t50.0' ]] ||
  fail update-bad "rc=$RC: $(cat "$D/tests/mutation-floor.tsv")"

echo "--- --update after a failing suite writes no floors"
setup; echo 'exit 1' >"$D/tests/test_broken.sh"; rm "$D/tests/mutation-floor.tsv"; mut --update
[[ $RC == 1 && ! -e $D/tests/mutation-floor.tsv ]] || fail update-red "rc=$RC: $OUTPUT"

echo "--- --update is refused with a file or --changed, and writes nothing"
setup; rm "$D/tests/mutation-floor.tsv"
refused() { [[ $RC == 2 && ! -e $D/tests/mutation-floor.tsv ]] || fail "$1" "rc=$RC: $OUTPUT"; }
mut --update "$M"; refused update-file
mut "$M" --update; refused update-after-file
mut --update --changed; refused update-changed
mut --changed --update; refused changed-update

finish "mutate-tools"
