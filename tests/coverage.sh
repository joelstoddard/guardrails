#!/usr/bin/env bash
# Line coverage for the plugins' hook scripts and lib files, checked against per-file floors that only rise.
# Usage: tests/coverage.sh [--update | [--base REV] --ratchet BASE_FLOOR_FILE [FLOOR_FILE] | --lines FILE | --files | --trace]
# See docs/design/coverage.md
set -euo pipefail
# Each sort and comm runs with LC_ALL=C, so hits.tsv sorts the same on every host. LC_ALL is not
# exported, so the traced suites keep the caller's locale.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd "${COVERAGE_ROOT:-$HERE/..}" && pwd -P)"
FLOORS="$ROOT/tests/coverage-floor.tsv"
OUT="$ROOT/.coverage"

die() { echo "coverage: $*" >&2; exit 2; }
((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 1))) || die "needs bash 4.1 or newer"

tenths() { # "87.5" -> 875; fails on anything but digits.digit, so a bad floor can never read as "no limit"
  [[ $1 =~ ^[0-9]+\.[0-9]$ ]] || return 1
  echo $((10#${1%.*} * 10 + 10#${1#*.}))
}
pct() { local t=$1; echo "$((t / 10)).$((t % 10))"; }            # 875 -> "87.5"
whole() { [[ $1 =~ ^[0-9]+$ ]]; }                                # a ceiling, a count of lines

measured() { # measured files, relative to ROOT
  (cd "$ROOT" && for f in plugins/*/hooks/scripts/*.sh plugins/*/lib/*.sh; do
    if [[ -f $f ]]; then echo "$f"; fi
  done) | LC_ALL=C sort
}

run_suites() { # every shell test under tracing, one log per test file; returns 1 if any test fails
  local t rc=0
  # From the root, as CI runs them, so the caller's directory changes no result; hits() then resolves traced paths here.
  cd "$ROOT" || return 1
  rm -rf "$OUT"; mkdir -p "$OUT/logs"
  [[ -z $awk_runs ]] || mkdir -p "$awk_runs"
  for t in "$ROOT"/tests/test_*.sh; do
    [[ -e $t ]] && { run_one "$t" "$(basename "$t")" || rc=1; }
  done
  return $rc
}

run_one() { # <test file> <name>; reports the result, and a failing suite's output, which CI shows in place of a test run
  # stdin is /dev/null, so the awk shim, which reads stdin for both its runs, never waits on a terminal.
  # GUARDRAILS_TIME_SCALE is mutate.sh's to set: here, as in CI, the wall-clock budgets hold at full strength.
  if COV_LOG="$OUT/logs/$2.log" COV_AWK="$awk_runs" BASH_ENV="$HERE/coverage/bash_env.sh" GUARDRAILS_TIME_SCALE='' \
    bash "$1" </dev/null >"$OUT/logs/$2.out" 2>&1; then
    echo "coverage: $2 passed"; return 0
  fi
  { echo "coverage: $2 failed, see $OUT/logs/$2.out"; cat "$OUT/logs/$2.out"; } >&2
  return 1
}

hits() { # writes "test<TAB>path<TAB>line" for each traced line of a file under ROOT
  local log raw dir
  declare -A rel_of
  for log in "$OUT"/logs/*.log; do
    [[ -e $log ]] || continue
    awk -v t="$(basename "$log" .log)" '
      match($0, /^\++[^:]+:[0-9]+/) {
        s = substr($0, 1, RLENGTH); sub(/^\++/, "", s)
        k = s; sub(/:[0-9]+$/, "", k); ln = substr(s, length(k) + 2)
        # A bash -c string names no file, so a line such as ++:1 has an empty path, which would resolve to the working directory.
        if (k != "") print t "\t" k "\t" ln
      }' "$log"
  done | LC_ALL=C sort -u >"$OUT/raw-hits.tsv"
  while IFS= read -r raw; do # resolve each distinct traced path once
    dir=$(cd "$(dirname "$raw")" 2>/dev/null && pwd -P) || continue
    [[ $dir/ == "$ROOT"/* ]] && rel_of[$raw]="${dir#"$ROOT"/}/$(basename "$raw")"
  done < <(cut -f2 "$OUT/raw-hits.tsv" | LC_ALL=C sort -u)
  while IFS=$'\t' read -r t raw ln; do
    if [[ -n ${rel_of[$raw]:-} ]]; then printf '%s\t%s\t%s\n' "$t" "${rel_of[$raw]}" "$ln"; fi
  done <"$OUT/raw-hits.tsv" | credit_spans | LC_ALL=C sort -u >"$OUT/hits.tsv"
}

credit_spans() { # stdin "test<TAB>path<TAB>line"; moves a hit on a command's later line to its counted line
  local f
  while IFS= read -r f; do
    awk -v spans=1 -f "$HERE/coverage/executable.awk" "$ROOT/$f" | awk -v p="$f" '{ print p "\t" $0 }'
  done < <(measured) >"$OUT/spans.tsv"
  awk -F'\t' -v OFS='\t' 'FILENAME == ARGV[1] { first[$1 FS $2] = $3; next } { k = $2 FS $3; if (k in first) $3 = first[k]; print }' "$OUT/spans.tsv" -
}

awk_rows() { # writes awk.tsv, "path<TAB>statements run<TAB>statements", from the gawk profiles of measured files' awk runs
  local run caller dir rel f bad=0
  declare -A measured_file rel_of
  while IFS= read -r f; do measured_file[$f]=1; done < <(measured)
  : >"$OUT/awk-missed.tsv"
  for run in "$awk_runs"/run.*.caller; do
    [[ -e $run ]] || continue
    IFS= read -r caller <"$run"; run=${run%.caller}
    if [[ -z ${rel_of[$caller]+set} ]]; then # resolve each caller once, as hits() does
      rel_of[$caller]=""
      if dir=$(cd "$(dirname "$caller")" 2>/dev/null && pwd -P) && [[ $dir/ == "$ROOT"/* ]]; then
        rel_of[$caller]="${dir#"$ROOT"/}/$(basename "$caller")"
      fi
    fi
    rel=${rel_of[$caller]}
    [[ -n $rel && -n ${measured_file[$rel]:-} ]] || continue
    # A run with no profile would read as nothing to measure, so it stops the report.
    if [[ -s $run.profile ]]; then printf '%s\t%s\n' "$rel" "$run.profile"
    else echo "coverage: gawk left no profile of an awk run from $rel, see $run.*" >&2; bad=1; fi
  done >"$OUT/awk-runs.tsv"
  ((!bad)) || return 1
  awk -v missed="$OUT/awk-missed.tsv" -f "$HERE/coverage/profiles.awk" "$OUT/awk-runs.tsv" | LC_ALL=C sort >"$OUT/awk.tsv"
  LC_ALL=C sort -o "$OUT/awk-missed.tsv" "$OUT/awk-missed.tsv"
}

floor_of() { awk -F'\t' -v p="$1" '$1 == p { print $2 }' "$FLOORS" 2>/dev/null || true; }
most_of() { awk -F'\t' -v p="$1" '$1 == p { print $3 }' "$FLOORS" 2>/dev/null || true; } # the ceiling on uncovered lines

report() { # <update: 0|1>; prints the table, rewrites floors on update, returns 1 on a missing or low floor
  local update=$1 f exec_n hit_n total_exec=0 total_hit=0 bad=0 invalid=0 status
  local -a rows=()
  printf '%-8s %9s %6s %6s %5s  %s\n' status lines pct floor most file
  while IFS= read -r f; do
    exec_n=$(awk -f "$HERE/coverage/executable.awk" "$ROOT/$f" | LC_ALL=C sort -u >"$OUT/exec" && wc -l <"$OUT/exec")
    awk -F'\t' -v p="$f" '$2 == p { print $3 }' "$OUT/hits.tsv" | LC_ALL=C sort -u >"$OUT/hit"
    hit_n=$(LC_ALL=C comm -12 <(LC_ALL=C sort "$OUT/exec") <(LC_ALL=C sort "$OUT/hit") | wc -l)
    exec_n=$((exec_n)); hit_n=$((hit_n))
    total_exec=$((total_exec + exec_n)); total_hit=$((total_hit + hit_n))
    row "$f" "$hit_n" "$exec_n"
  done < <(measured)
  row TOTAL "$total_hit" "$total_exec"
  while IFS=$'\t' read -r f hit_n exec_n; do row "awk:$f" "$hit_n" "$exec_n"; done <"$OUT/awk.tsv"
  if ((update && !invalid)); then printf '%s\n' "${rows[@]}" >"$FLOORS"; fi
  return $bad
}

row() { # <file or TOTAL> <hit> <executable>; prints its row and adds its floors to rows; report's bad and invalid see it
  local now=$(($3 == 0 ? 1000 : $2 * 1000 / $3)) uncovered=$(($3 - $2)) floor most
  floor=$(floor_of "$1"); most=$(most_of "$1")
  check "$now" "$floor" "$uncovered" "$most" || bad=1
  [[ $status == BAD ]] && invalid=1
  printf '%-8s %4d/%-4d %6s %6s %5s  %s\n' "$status" "$2" "$3" "$(pct "$now")" "${floor:--}" "${most:--}" "$1"
  rows+=("$1"$'\t'"$(pct "$(newfloor "$now" "$floor")")"$'\t'"$(newmost "$uncovered" "$most")")
}

check() { # <now, tenths> <floor or empty> <uncovered lines> <ceiling or empty>; sets status
  if [[ -z $2 ]]; then
    status="NO FLOOR"; ((update)) && return 0; return 1
  fi
  local floor_tenths
  floor_tenths=$(tenths "$2") || { status="BAD"; return 1; }
  if [[ -n $4 ]] && ! whole "$4"; then status="BAD"; return 1; fi
  status="ok"
  (($1 >= floor_tenths)) && return 0
  # Deleting covered lines lowers a percentage and tests nothing less, so a row also passes while its uncovered lines
  # stay within its ceiling. See docs/design/coverage.md
  [[ -n $4 ]] && (($3 <= 10#$4)) && return 0
  status="LOW"; return 1
}

newfloor() { # <now> <floor>: the higher of the two, in tenths
  local now=$1 floor_tenths
  if floor_tenths=$(tenths "${2:-}") && ((floor_tenths > now)); then now=$floor_tenths; fi
  echo "$now"
}

newmost() { # <uncovered lines> <ceiling or empty>: the lower of the two
  if whole "${2:-}" && ((10#$2 < $1)); then echo "$((10#$2))"; else echo "$1"; fi
}

moved_to() { # <path>: where a gone file went, per git since --base, else a file with its name; empty if deleted
  if [[ -n ${renamed[$1]+set} ]]; then echo "${renamed[$1]}"; return 0; fi
  local files f found=""
  files=$(cd "$ROOT" && git ls-files --cached --others --exclude-standard) || return 1
  while IFS= read -r f; do
    [[ ${f##*/} == "${1##*/}" && -f $ROOT/$f ]] || continue
    if [[ -n $(floor_of "$f") ]]; then echo "$f"; return 0; fi
    found=$f
  done <<<"$files"
  echo "$found"
}

ratchet() { # <base floor file>: fails if a floor fell, or vanished while its file still exists, here or moved
  local path old oldmost key file prefix new newmost new_tenths old_tenths moved bad=0 base_total=0 changes st a b
  declare -A renamed=() # path at --base -> its path now, or "" if deleted
  if [[ -n $base_rev ]]; then
    changes=$(mktemp) || return 1
    if ! (cd "$ROOT" && git diff --find-renames --name-status -z "$base_rev" --) >"$changes"; then
      echo "cannot diff against $base_rev"; rm -f "$changes"; return 1
    fi
    while IFS= read -r -d '' st && IFS= read -r -d '' a; do
      case $st in
        R*) IFS= read -r -d '' b && renamed[$a]=$b ;;
        D) renamed[$a]="" ;;
      esac
    done <"$changes"
    rm -f "$changes"
  fi
  while IFS=$'\t' read -r path old oldmost || [[ -n $path ]]; do
    [[ -n $path ]] || continue
    [[ $path == TOTAL ]] && base_total=1
    key=$path; new=$(floor_of "$key")
    file=${path#awk:}; prefix=${path%"$file"} # an awk row, awk:FILE, follows its file
    if [[ -z $new && $path != TOTAL && ! -e $ROOT/$file ]]; then # renamed per git, or moved with its name
      moved=$(moved_to "$file") || { echo "cannot list the repo's files to find $file"; bad=1; continue; }
      [[ -n $moved ]] || continue # deleted, so its floor may go
      file=$moved; key=$prefix$moved; new=$(floor_of "$key"); path="$path -> $key"
    fi
    # An awk row's floor may go once its file names no awk.
    if [[ -z $new && -n $prefix ]] && ! grep -qw awk "$ROOT/$file" 2>/dev/null; then continue; fi
    if [[ -z $new ]]; then echo "floor removed: $path (was $old)"; bad=1; continue; fi
    if ! new_tenths=$(tenths "$new") || ! old_tenths=$(tenths "$old"); then
      echo "floor invalid: $path"; bad=1
    elif ((new_tenths < old_tenths)); then
      echo "floor lowered: $path $old -> $new"; bad=1
    fi
    [[ -n $oldmost ]] || continue # a base from before the ceilings has none to compare
    newmost=$(most_of "$key")
    if [[ -z $newmost ]]; then echo "ceiling removed: $path (was $oldmost)"; bad=1
    elif ! whole "$newmost" || ! whole "$oldmost"; then echo "floor invalid: $path"; bad=1
    elif ((10#$newmost > 10#$oldmost)); then echo "ceiling raised: $path $oldmost -> $newmost"; bad=1; fi
  done <"$1"
  # An empty base, such as a failed git show, would otherwise compare nothing and pass.
  if ((!base_total)); then echo "base has no TOTAL floor: $1"; bad=1; fi
  return $bad
}

base_rev="" awk_runs=""
if [[ ${1:-} == --base ]]; then
  base_rev=${2:?--base needs a revision}; shift 2
  [[ ${1:-} == --ratchet ]] || die "--base goes only with --ratchet"
fi
case ${1:-} in
  --lines) awk -f "$HERE/coverage/executable.awk" "${2:?--lines needs a file}" ;;
  --ratchet) FLOORS=${3:-$FLOORS}; ratchet "${2:?--ratchet needs the base floor file}" ;;
  --files) measured ;;
  --trace) run_suites || exit 1; hits ;;
  --update | "")
    update=0; [[ ${1:-} == --update ]] && update=1
    command -v gawk >/dev/null || die "needs gawk, to measure the awk programs in the measured files"
    awk_runs=$OUT/awk
    run_suites || exit 1
    hits
    awk_rows || exit 1
    report "$update"
    ;;
  *) die "unknown option: $1" ;;
esac
