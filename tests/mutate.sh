#!/usr/bin/env bash
# Mutation testing for the hook scripts and lib files: a mutant survives when every test that runs its line still passes.
# Usage: tests/mutate.sh [-j N] [--update | --changed [REV] | FILE...]
# See docs/design/coverage.md
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd "${COVERAGE_ROOT:-$HERE/..}" && pwd -P)"
OUT="$ROOT/.coverage"
IGNORE="$ROOT/tests/mutants-ignore.tsv"
FLOORS="$ROOT/tests/mutation-floor.tsv"
SEP=$'\034'
# Workers load every CPU, so a test's wall-clock budget is stretched as far as the hang limit below: a mutant is judged
# on what the tests assert, not on speed. See docs/design/coverage.md
TIME_SCALE=10

die() { echo "mutate: $*" >&2; exit 2; }
fail() { echo "mutate: $*" >&2; exit 1; }
((BASH_VERSINFO[0] >= 5)) || die "needs bash 5 or newer (EPOCHREALTIME)"
score() { echo $(($2 == 0 ? 1000 : $1 * 1000 / $2)); }  # killed, scored -> tenths of a percent
pct() { echo "$(($1 / 10)).$(($1 % 10))"; }              # 875 -> "87.5"
tenths() { # "87.5" -> 875; fails on anything but digits.digit, so a bad floor can never read as "no limit"
  [[ $1 =~ ^[0-9]+\.[0-9]$ ]] || return 1
  echo $((10#${1%.*} * 10 + 10#${1#*.}))
}
whole() { [[ $1 =~ ^[0-9]+$ ]]; }                         # a ceiling, a count of survivors
trim() { local s=$1; s=${s#"${s%%[![:space:]]*}"}; printf '%s\n' "${s%"${s##*[![:space:]]}"}"; }

targets() { # fills files[] with the measured files to mutate; runs in the main shell so die stops the run
  local -a all
  local listing
  listing=$(bash "$HERE/coverage.sh" --files) || fail "coverage.sh --files failed"
  mapfile -t all < <(printf '%s' "$listing")
  case ${1:-} in
    "") files=("${all[@]}") ;;
    --update)
      (($# == 1)) || die "--update takes no other arguments, because only a full run has a total"
      files=("${all[@]}")
      ;;
    --changed)
      (($# <= 2)) || die "--changed takes at most a revision"
      local base
      # With a revision, as in CI, compare with it; without one, with where this branch left origin/main.
      if (($# == 2)); then base=$2; else base=$(git -C "$ROOT" merge-base origin/main HEAD 2>/dev/null) || die "--changed needs origin/main"; fi
      local changed
      changed=$({ git -C "$ROOT" diff --name-only "$base" -- && git -C "$ROOT" ls-files --others --exclude-standard; } | sort -u) ||
        die "--changed cannot diff against $base"
      mapfile -t files < <(comm -12 <(printf '%s\n' "${all[@]}" | sort) <(printf '%s\n' "$changed"))
      ;;
    *)
      local f
      for f in "$@"; do
        printf '%s\n' "${all[@]}" | grep -qxF -- "$f" || die "not a measured file: $f"
        printf '%s\n' "${files[@]}" | grep -qxF -- "$f" && continue
        files+=("$f")
      done
      ;;
  esac
}

load_ignores() { # fills ignored[file SEP operator SEP trimmed line]; every row needs a reason
  local file op text reason n=0
  [[ -e $IGNORE ]] || return 0
  while IFS=$'\t' read -r file op text reason || [[ -n $file ]]; do
    n=$((n + 1))
    [[ -z $file || $file == \#* ]] && continue
    [[ -n $reason ]] || die "$IGNORE line $n has no reason"
    ignored["$file$SEP$op$SEP$text"]=1
  done <"$IGNORE"
}

plan() { # writes $OUT/plan: file SEP line SEP operator SEP mutated line, for every covered executable line
  local f covered executable
  : >"$OUT/plan"
  for f in "${files[@]}"; do
    executable=$(bash "$HERE/coverage.sh" --lines "$ROOT/$f") || fail "coverage.sh --lines failed on $f"
    covered=$(comm -12 <(sort -u <<<"$executable") \
      <(awk -F'\t' -v p="$f" '$2 == p { print $3 }' "$OUT/hits.tsv" | sort -u) | paste -sd, -)
    if [[ -z $covered ]]; then
      [[ -z $executable ]] || fail "$f has no covered line; did its tests run?"
      continue
    fi
    awk -v lines=",$covered," -f "$HERE/coverage/mutants.awk" "$ROOT/$f" | awk -v f="$f" '{ print f "\034" $0 }' >>"$OUT/plan"
  done
}

copy_tree() { # <dir>: a scratch copy of the working tree, so a mutant never touches the checkout
  if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    (cd "$ROOT" && git ls-files -z -co --exclude-standard |
      while IFS= read -r -d '' p; do [[ -e $p ]] || continue; printf '%s\0' "$p"; done | tar --null -T - -cf -) |
      tar -xf - -C "$1"
  else
    (cd "$ROOT" && tar --exclude ./.coverage -cf - .) | tar -xf - -C "$1"
  fi
}

run_test() { # <copy> <test name from hits.tsv> <seconds>: runs that test in the copy with a time limit
  [[ $2 == test_*.sh && $2 != */* ]] || die "unknown test name: $2"
  # A hung mutant must leave nothing running, so the wrapper kills the test's process group on exit,
  # timeout, HUP, INT and TERM. A timeout exits 124, which counts as killed.
  perl -e '
    my $t = shift; my $p = fork // die "fork: $!";
    if (!$p) { setpgrp(0, 0); exec @ARGV or exit 127 }
    $SIG{ALRM} = sub { kill "KILL", -$p; waitpid $p, 0; exit 124 };
    $SIG{$_} = sub { kill "KILL", -$p; exit 1 } for qw(HUP INT TERM);
    alarm $t; waitpid $p, 0; my $s = $?; alarm 0; kill "KILL", -$p;
    exit($s & 127 ? 128 + ($s & 127) : $s >> 8);
  ' "$3" env COV_LOG= GUARDRAILS_TIME_SCALE="$TIME_SCALE" bash "$1/tests/$2" </dev/null >/dev/null 2>&1
}

baseline() { # <copy>: times each test the plan needs, unmutated; a red test stops the run
  local t start
  while IFS= read -r t; do
    start=$EPOCHREALTIME
    run_test "$1" "$t" 600 || fail "baseline red: $t fails without any mutant"
    # TIME_SCALE times the clean run, and at least 2s, before a mutant counts as hanging.
    limit[$t]=$(LC_ALL=C awk -v a="$start" -v b="$EPOCHREALTIME" -v k="$TIME_SCALE" 'BEGIN { s = int((b - a) * k) + 1; print (s < 2 ? 2 : s) }')
  done < <(awk -v sep="$SEP" 'NR == FNR { split($0, p, sep); want[p[1] "\t" p[2]] = 1; next }
    { split($0, h, "\t"); if ((h[2] "\t" h[3]) in want) print h[1] }' "$OUT/plan" "$OUT/hits.tsv" | sort -u)
}

worker() { # <index> <copy>: runs every plan line whose number is index modulo jobs; writes results.<index>
  local k=$1 copy=$2 f ln op mutated original status t rc n=0
  while IFS="$SEP" read -r f ln op mutated; do
    n=$((n + 1))
    (((n - 1) % jobs == k)) || continue
    original=$(sed -n "${ln}p" "$ROOT/$f")
    if [[ -n ${ignored["$f$SEP$op$SEP$(trim "$original")"]:-} ]]; then
      status=ignored
    else
      # Through ENVIRON, not -v: awk would turn the line's backslash escapes into other characters.
      MUTANT=$mutated awk -v n="$ln" 'NR == n { print ENVIRON["MUTANT"]; next } { print }' "$ROOT/$f" >"$copy/$f"
      if bash -n "$copy/$f" 2>/dev/null; then
        status=survived
        while IFS= read -r t; do
          rc=0; run_test "$copy" "$t" "${limit[$t]}" || rc=$?
          # 127 and 255 are the wrapper's own failures (exec, fork), not a test that caught the mutant.
          ((rc == 127 || rc == 255)) && { echo "mutate: test wrapper failed with $rc on $t" >&2; return 1; }
          ((rc == 0)) && continue
          status=killed; break
        done < <(awk -F'\t' -v p="$f" -v l="$ln" '$2 == p && $3 == l { print $1 }' "$OUT/hits.tsv" | fastest_first)
      else
        status=invalid
      fi
      cp "$ROOT/$f" "$copy/$f"
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$status" "$f" "$ln" "$op" "$(trim "$original")" "$(trim "$mutated")"
  done <"$OUT/plan" >"$OUT/results.$k"
}

fastest_first() { # stdin: test names; a kill stops at the first test that fails, so the quickest go first
  local t
  while IFS= read -r t; do printf '%s\t%s\n' "${limit[$t]}" "$t"; done | sort -t$'\t' -k1,1n -k2,2 | cut -f2
}

floor_of() { awk -F'\t' -v p="$1" '$1 == p { print $2 }' "$FLOORS" 2>/dev/null || true; }
most_of() { awk -F'\t' -v p="$1" '$1 == p { print $3 }' "$FLOORS" 2>/dev/null || true; } # the ceiling on survivors

check() { # <now, tenths> <floor or empty> <survivors> <ceiling or empty>; sets status
  if [[ -z $2 ]]; then
    status="NO FLOOR"; ((update)) && return 0; return 1
  fi
  local floor_tenths
  floor_tenths=$(tenths "$2") || { status="BAD"; return 1; }
  if [[ -n $4 ]] && ! whole "$4"; then status="BAD"; return 1; fi
  status="ok"
  (($1 >= floor_tenths)) && return 0
  # Deleting code whose mutants were killed lowers a score and tests nothing less, so a row also passes while its
  # survivors stay within its ceiling. See docs/design/coverage.md
  [[ -n $4 ]] && (($3 <= 10#$4)) && return 0
  status="LOW"; return 1
}

newfloor() { # <now> <floor>: the higher of the two, in tenths
  local now=$1 floor_tenths
  if floor_tenths=$(tenths "${2:-}") && ((floor_tenths > now)); then now=$floor_tenths; fi
  echo "$now"
}

newmost() { # <survivors> <ceiling or empty>: the lower of the two
  if whole "${2:-}" && ((10#$2 < $1)); then echo "$((10#$2))"; else echo "$1"; fi
}

row() { # <label> <killed> <scored>; prints a table row; report's bad, invalid and rows see the result
  local now floor most survived=$(($3 - $2))
  now=$(score "$2" "$3"); floor=$(floor_of "$1"); most=$(most_of "$1")
  check "$now" "$floor" "$survived" "$most" || bad=1
  [[ $status == BAD ]] && invalid=1
  printf '%9s %6s %6s %5s  %-8s  %s\n' "$2/$3" "$(pct "$now")" "${floor:--}" "${most:--}" "$status" "$1"
  rows+=("$1"$'\t'"$(pct "$(newfloor "$now" "$floor")")"$'\t'"$(newmost "$survived" "$most")")
}

report() { # <update: 0|1>; table with floors, survivors after it; returns 1 on a missing, low or bad floor
  local update=$1 f k=0 n=0 fk fn bad=0 invalid=0 status
  local -a rows=()
  printf '%9s %6s %6s %5s  %-8s  %s\n' killed score floor most status file
  for f in "${files[@]}"; do
    fk=$(awk -F'\t' -v p="$f" '$2 == p && $1 == "killed"' "$OUT/mutants.tsv" | wc -l)
    fn=$(awk -F'\t' -v p="$f" '$2 == p && ($1 == "killed" || $1 == "survived")' "$OUT/mutants.tsv" | wc -l)
    fk=$((fk)); fn=$((fn)); k=$((k + fk)); n=$((n + fn))
    row "$f" "$fk" "$fn"
  done
  ((full)) && row TOTAL "$k" "$n"
  awk -F'\t' '$1 == "survived" { if (!s++) print ""; printf "survived  %s:%s  %s  %s  ->  %s\n", $2, $3, $4, $5, $6 }' "$OUT/mutants.tsv"
  if ((update && !invalid)); then printf '%s\n' "${rows[@]}" >"$FLOORS"; fi
  return $bad
}

jobs=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)
if [[ ${1:-} == -j ]]; then jobs=${2:-}; shift $(($# > 1 ? 2 : 1)); fi
[[ $jobs =~ ^[1-9][0-9]*$ ]] || die "-j needs a positive number"
declare -A ignored limit
declare -a files=()
update=0 full=0
case ${1:-} in --update) update=1 full=1 ;; "") full=1 ;; esac
load_ignores
targets "$@"
((${#files[@]})) || { echo "mutate: no measured files to mutate"; exit 0; }
for f in "${files[@]}"; do bash -n "$ROOT/$f" 2>/dev/null || fail "$f does not parse, so every mutant of it would be invalid"; done
bash "$HERE/coverage.sh" --trace >/dev/null || fail "the suites fail; fix them before mutating"
plan
WORK=$(mktemp -d)
pids=()
# Workers ignore INT, so they outlive the main shell; their wrappers get TERM first and kill the tests.
# The trap does not signal the process group, because the caller can share it.
stop_workers() {
  local p
  for p in "${pids[@]}"; do pkill -TERM -P "$p" 2>/dev/null || true; kill "$p" 2>/dev/null || true; done
}
trap 'stop_workers; rm -rf "$WORK"' EXIT
mkdir "$WORK/0"; copy_tree "$WORK/0"
baseline "$WORK/0"
for ((i = 0; i < jobs; i++)); do
  [[ -d $WORK/$i ]] || { mkdir "$WORK/$i"; copy_tree "$WORK/$i"; }
  worker "$i" "$WORK/$i" &
  pids+=("$!")
done
for p in "${pids[@]}"; do wait "$p" || fail "a mutation worker failed"; done
sort -t$'\t' -k2,2 -k3,3n "$OUT"/results.* >"$OUT/mutants.tsv"
rm -f "$OUT"/results.*
report "$update"
