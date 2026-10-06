#!/usr/bin/env bash
# Tests tests/coverage.sh against small fixture repos: tracing, the executable-line heuristic, floors
# and the ratchet. See docs/design/coverage.md
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/helper.sh"
TOOL="$DIR/coverage.sh"
S=plugins/p/hooks/scripts/f.sh

fail() { echo "  FAIL [$1]: $2"; FAILS=1; }

setup() { # → a fixture repo in $D with one measured hook script and its test
  D="$(scratch_dir)"; mkdir -p "$D/plugins/p/hooks/scripts" "$D/plugins/p/lib" "$D/tests"
  cat >"$D/$S" <<'EOF'
# fixture
if [[ ${1:-} == yes ]]; then
  echo "took yes"
else
  echo "took no"
fi
EOF
  cat >"$D/tests/test_f.sh" <<'EOF'
[[ $(bash "$(dirname "$0")/../plugins/p/hooks/scripts/f.sh" yes) == "took yes" ]]
EOF
}
cov() { OUTPUT="$(COVERAGE_ROOT="$D" bash "$TOOL" "$@" 2>&1)"; RC=$?; }
row() { printf '%s\n' "$OUTPUT" | awk -v f="$1" '$NF == f { print $(NF-3), $(NF-2), $1 }'; } # → "hit/exec pct status"
floors() { cat "$D/tests/coverage-floor.tsv"; }

# On a bash older than 4.1 every case below would fail with an empty row, so stop with the tool's reason.
why="$(bash "$TOOL" --lines /dev/null 2>&1)" || { fail "the bash on PATH runs the tool" "$why"; finish "coverage-tools"; }

echo "--- a branch the test never takes counts against coverage"
setup; cov --update
assert_eq "2/3 66.6 NO" "$(row "$S")" "branch"

echo "--- a lib sourced by a test is traced, functions included"
setup
cat >"$D/plugins/p/lib/g.sh" <<'EOF'
pick() {
  if [[ $1 == yes ]]; then
    echo "took yes"
  else
    echo "took no"
  fi
}
EOF
cat >"$D/tests/test_g.sh" <<'EOF'
. "$(dirname "$0")/../plugins/p/lib/g.sh"
[[ $(pick yes) == "took yes" ]]
EOF
cov --update
assert_eq "2/3 66.6 NO" "$(row plugins/p/lib/g.sh)" "sourced lib"

echo "--- comments, keywords, heredoc bodies, string continuations and ignored lines are not executable"
D="$(scratch_dir)"
cat >"$D/h.sh" <<'EOF'
# a comment
for x in a b; do
  echo "$x"
done
cat <<'BODY'
if this were code
BODY
jq -n '
  1 + 1'
case $1 in
  a | b)
    echo ab
    ;;
  c) ;;
esac
exit 3 # coverage: ignore unreachable after the case above
f() {
  echo in-f
}
EOF
assert_eq "2 3 5 8 10 12 18 " "$(bash "$TOOL" --lines "$D/h.sh" | tr '\n' ' ')" "heuristic"

echo "--- a case label continued with a backslash is not executable, and the line it continues to is read on its own"
D="$(scratch_dir)"
cat >"$D/c.sh" <<'EOF'
case $1 in
  -a | -b | \
    -c) echo abc ;;
  -d | \
    -e | \
    -f)
    echo def
    ;;
esac
EOF
assert_eq "1 3 7 " "$(bash "$TOOL" --lines "$D/c.sh" | tr '\n' ' ')" "continued-case-label"

echo "--- a shift inside (( )) or \$(( )) opens no heredoc, and a heredoc after a closing )) still does"
D="$(scratch_dir)"
cat >"$D/a.sh" <<'EOF'
(( x << y ))
echo after-arith
z=$(( x << y ))
echo after-expansion
(( x )) && cat <<BODY
not code
BODY
d=$(dirname $(pwd)) && cat <<BODY
not code
BODY
echo after-heredocs
(( x +
  y << z ))
echo after-two-lines
EOF
assert_eq "1 2 3 4 5 8 11 12 13 14 " "$(bash "$TOOL" --lines "$D/a.sh" | tr '\n' ' ')" "arith-shift"

echo "--- a hit on a later line of a multi-line command is credited to the command's counted line"
setup
cat >"$D/$S" <<'EOF'
x=$(printf '%s' "a
b")
echo one \
  two
echo "c
d" | cat
EOF
echo 'bash "$(dirname "$0")/../plugins/p/hooks/scripts/f.sh" >/dev/null' >"$D/tests/test_f.sh"
cov --update
assert_eq "3/3 100.0 NO" "$(row "$S")" "span-credit"
assert_eq "1 3 5 " "$(awk -F'\t' -v p="$S" '$2 == p { print $3 }' "$D/.coverage/hits.tsv" | tr '\n' ' ')" "span-hits"

echo "--- a multi-line command the test never reaches stays uncovered"
setup
cat >"$D/$S" <<'EOF'
if [[ ${1:-} == yes ]]; then
  echo "took yes"
else
  echo "took no \
  twice"
fi
EOF
cov --update
assert_eq "2/3 66.6 NO" "$(row "$S")" "span-uncovered"

echo "--- a hit on the continuation of a line that does not count credits no earlier command"
setup
cat >"$D/$S" <<'EOF'
if [[ ${1:-} == yes ]]; then
  echo "took yes"
else x="took
no"
fi
EOF
echo 'bash "$(dirname "$0")/../plugins/p/hooks/scripts/f.sh" no' >"$D/tests/test_f.sh"
cov --update
assert_eq "1/2 50.0 NO" "$(row "$S")" "span-uncounted"
assert_eq "1 4 " "$(awk -F'\t' -v p="$S" '$2 == p { print $3 }' "$D/.coverage/hits.tsv" | tr '\n' ' ')" "span-uncounted-hits"

echo "--- a measured file with no executable lines counts as fully covered"
setup; echo '# only a comment' >"$D/plugins/p/lib/empty.sh"; cov --update
assert_eq "0/0 100.0 NO" "$(row plugins/p/lib/empty.sh)" "empty"

echo "--- a failing test stops the run"
setup; echo 'exit 1' >"$D/tests/test_broken.sh"; cov
[[ $RC == 1 && $OUTPUT == *"test_broken.sh failed"* ]] || fail red-suite "rc=$RC: $OUTPUT"

echo "--- a measured file without a floor fails"
setup; cov
[[ $RC == 1 && $(row "$S") == *"NO" ]] || fail no-floor "rc=$RC: $OUTPUT"

echo "--- --update records floors for the hook scripts and libs only, after which the check passes"
setup; mkdir -p "$D/plugins/p/bin"; echo 'echo unmeasured' >"$D/plugins/p/bin/other.sh"
cov --update; cov
[[ $RC == 0 ]] || fail update "rc=$RC: $OUTPUT"
assert_eq "$S"$'\t66.6\nTOTAL\t66.6' "$(floors)" "update writes exactly the measured floors"

echo "--- coverage below its floor fails, and --update never lowers the floor"
setup; printf '%s\t90.0\nTOTAL\t66.6\n' "$S" >"$D/tests/coverage-floor.tsv"; cov
[[ $RC == 1 && $(row "$S") == *"LOW" ]] || fail low "rc=$RC: $OUTPUT"
cov --update
[[ $RC == 1 && $(floors) == *$'f.sh\t90.0'* ]] || fail no-lowering "rc=$RC, floors '$(floors)'"

echo "--- the ratchet fails on a lowered or vanished floor, and passes otherwise"
setup; git -C "$D" init -q
printf '%s\t66.6\nTOTAL\t66.6\n' "$S" >"$D/tests/coverage-floor.tsv"
printf '%s\t70.0\nTOTAL\t66.6\n' "$S" >"$D/base.tsv"; cov --ratchet "$D/base.tsv"
[[ $RC == 1 && $OUTPUT == *"floor lowered: $S"* ]] || fail ratchet-lowered "rc=$RC: $OUTPUT"
printf '%s\t66.6\nplugins/p/lib/gone.sh\t50.0\nTOTAL\t66.6\n' "$S" >"$D/base.tsv"; cov --ratchet "$D/base.tsv"
[[ $RC == 0 ]] || fail ratchet-deleted-file "rc=$RC: $OUTPUT"
echo 'kept' >"$D/plugins/p/lib/gone.sh"; git -C "$D" add plugins/p/lib/gone.sh; rm "$D/plugins/p/lib/gone.sh"
cov --ratchet "$D/base.tsv"
[[ $RC == 0 ]] || fail ratchet-deleted-unstaged "rc=$RC: $OUTPUT"
echo 'kept' >"$D/plugins/p/lib/gone.sh"; cov --ratchet "$D/base.tsv"
[[ $RC == 1 && $OUTPUT == *"floor removed: plugins/p/lib/gone.sh"* ]] || fail ratchet-removed "rc=$RC: $OUTPUT"
printf '%s\t60.0\nTOTAL\t60.0\n' "$S" >"$D/base.tsv"; cov --ratchet "$D/base.tsv"
[[ $RC == 0 ]] || fail ratchet-raised "rc=$RC: $OUTPUT"
printf '%s\t66.6\n' "$S" >"$D/tests/coverage-floor.tsv"
printf '%s\t66.6\nTOTAL\t66.6\n' "$S" >"$D/base.tsv"; cov --ratchet "$D/base.tsv"
[[ $RC == 1 && $OUTPUT == *"floor removed: TOTAL"* ]] || fail ratchet-total "rc=$RC: $OUTPUT"

echo "--- the ratchet fails on a floor whose file moved out of the measured paths"
setup; git -C "$D" init -q; mkdir -p "$D/plugins/p/moved"; echo true >"$D/plugins/p/moved/m.sh"
printf '%s\t66.6\nTOTAL\t66.6\n' "$S" >"$D/tests/coverage-floor.tsv"
printf '%s\t66.6\nplugins/p/lib/m.sh\t50.0\nTOTAL\t66.6\n' "$S" >"$D/base.tsv"; cov --ratchet "$D/base.tsv"
[[ $RC == 1 && $OUTPUT == *"floor removed: plugins/p/lib/m.sh -> plugins/p/moved/m.sh (was 50.0)"* ]] ||
  fail ratchet-moved-out "rc=$RC: $OUTPUT"

echo "--- the ratchet follows a floor whose file moved to another measured path, past an unmeasured namesake, and fails if it fell"
setup; git -C "$D" init -q; mkdir -p "$D/plugins/q/lib"; echo true >"$D/plugins/q/lib/m.sh"; echo true >"$D/plugins/p/m.sh"
printf '%s\t66.6\nplugins/p/lib/m.sh\t50.0\nTOTAL\t66.6\n' "$S" >"$D/base.tsv"
printf '%s\t66.6\nplugins/q/lib/m.sh\t50.0\nTOTAL\t66.6\n' "$S" >"$D/tests/coverage-floor.tsv"; cov --ratchet "$D/base.tsv"
[[ $RC == 0 ]] || fail ratchet-moved-measured "rc=$RC: $OUTPUT"
printf '%s\t66.6\nplugins/q/lib/m.sh\t40.0\nTOTAL\t66.6\n' "$S" >"$D/tests/coverage-floor.tsv"; cov --ratchet "$D/base.tsv"
[[ $RC == 1 && $OUTPUT == *"floor lowered: plugins/p/lib/m.sh -> plugins/q/lib/m.sh 50.0 -> 40.0"* ]] ||
  fail ratchet-moved-lowered "rc=$RC: $OUTPUT"

echo "--- the ratchet fails on a vanished floor when it cannot list the repo's files to look for it"
setup
printf '%s\t66.6\nTOTAL\t66.6\n' "$S" >"$D/tests/coverage-floor.tsv"
printf '%s\t66.6\nplugins/p/lib/m.sh\t50.0\nTOTAL\t66.6\n' "$S" >"$D/base.tsv"; cov --ratchet "$D/base.tsv"
[[ $RC == 1 && $OUTPUT == *"cannot list the repo's files"* ]] || fail ratchet-no-git "rc=$RC: $OUTPUT"

echo "--- the ratchet fails on a base floor file that is missing or empty, so there is always a base to compare"
setup; printf '%s\t66.6\nTOTAL\t66.6\n' "$S" >"$D/tests/coverage-floor.tsv"; cov --ratchet "$D/missing.tsv"
[[ $RC == 1 ]] || fail ratchet-no-base "rc=$RC: $OUTPUT"
: >"$D/base.tsv"; cov --ratchet "$D/base.tsv"
[[ $RC == 1 && $OUTPUT == *"base has no TOTAL floor"* ]] || fail ratchet-empty-base "rc=$RC: $OUTPUT"

echo "--- a file run through a symlinked path is credited to its real path"
setup; ln -s "$D/plugins/p/hooks/scripts" "$D/alias"
cat >"$D/tests/test_f.sh" <<'EOF'
[[ $(bash "$(dirname "$0")/../alias/f.sh" yes) == "took yes" ]]
EOF
cov --update
assert_eq "2/3 66.6 NO" "$(row "$S")" "symlink"

echo "--- the tracer records exactly the lines the test ran, under the test's name"
setup; cov --update
assert_eq $'test_f.sh\t'"$S"$'\t2\ntest_f.sh\t'"$S"$'\t3' "$(grep "$S" "$D/.coverage/hits.tsv")" "hits rows"

echo "--- a path with two floors fails the check and the ratchet"
setup
printf '%s\t99.9\n%s\t10.0\nTOTAL\t66.6\n' "$S" "$S" >"$D/tests/coverage-floor.tsv"; cov
[[ $RC == 1 ]] || fail duplicate-floor "check rc=$RC: $OUTPUT"
printf '%s\t99.9\nTOTAL\t66.6\n' "$S" >"$D/base.tsv"; cov --ratchet "$D/base.tsv"
[[ $RC == 1 && $OUTPUT == *"floor invalid: $S"* ]] || fail duplicate-floor-ratchet "rc=$RC: $OUTPUT"

echo "--- a floor that is not a number fails the check and the ratchet"
setup
printf '%s\t66.6\nTOTAL\tn/a\n' "$S" >"$D/tests/coverage-floor.tsv"; cov
[[ $RC == 1 ]] || fail malformed-floor "check rc=$RC: $OUTPUT"
printf '%s\t66.6\nTOTAL\t99.9\n' "$S" >"$D/base.tsv"; cov --ratchet "$D/base.tsv"
[[ $RC == 1 && $OUTPUT == *"floor invalid: TOTAL"* ]] || fail malformed-floor-ratchet "rc=$RC: $OUTPUT"

echo "--- --update leaves a floor file with a malformed value untouched"
setup; printf '%s\t66.6\nTOTAL\tn/a\n' "$S" >"$D/tests/coverage-floor.tsv"; cov --update
[[ $RC == 1 && $(floors) == "$S"$'\t66.6\nTOTAL\tn/a' ]] || fail update-malformed "rc=$RC, floors '$(floors)'"

echo "--- a traced file outside the repo, sorted last, does not abort the run"
setup; O="${D}0"; mkdir "$O"; echo true >"$O/s.sh"
echo "bash $O/s.sh" >"$D/tests/test_z.sh"
cov --update
[[ $RC == 0 && $(row "$S") == "2/3 66.6 NO" ]] || fail outside-last "rc=$RC: $OUTPUT"

echo "--- --update raises an existing floor to the current value"
setup; printf '%s\t50.0\nTOTAL\t50.0\n' "$S" >"$D/tests/coverage-floor.tsv"; cov --update
assert_eq "$S"$'\t66.6\nTOTAL\t66.6' "$(floors)" "raise"

echo "--- the ratchet fails on a last base row with no trailing newline"
setup
printf '%s\t66.6\nTOTAL\t66.6\n' "$S" >"$D/tests/coverage-floor.tsv"
printf '%s\t66.6\nTOTAL\t99.9' "$S" >"$D/base.tsv"; cov --ratchet "$D/base.tsv"
[[ $RC == 1 && $OUTPUT == *"floor lowered: TOTAL"* ]] || fail ratchet-no-newline "rc=$RC: $OUTPUT"

finish "coverage-tools"
