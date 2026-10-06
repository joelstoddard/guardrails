#!/usr/bin/env bash
# Line coverage for the plugins' hook scripts and lib files, checked against per-file floors that only rise.
# Usage: tests/coverage.sh [--update | --ratchet BASE_FLOOR_FILE | --lines FILE]
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

measured() { # measured files, relative to ROOT
  (cd "$ROOT" && for f in plugins/*/hooks/scripts/*.sh plugins/*/lib/*.sh; do
    if [[ -f $f ]]; then echo "$f"; fi
  done) | LC_ALL=C sort
}

run_suites() { # every shell test under tracing, one log per test file; returns 1 if any test fails
  local t rc=0
  rm -rf "$OUT"; mkdir -p "$OUT/logs"
  for t in "$ROOT"/tests/test_*.sh; do
    [[ -e $t ]] && { run_one "$t" "$(basename "$t")" || rc=1; }
  done
  return $rc
}

run_one() { # <test file> <name>
  COV_LOG="$OUT/logs/$2.log" BASH_ENV="$HERE/coverage/bash_env.sh" bash "$1" >"$OUT/logs/$2.out" 2>&1 && return 0
  echo "coverage: $2 failed, see $OUT/logs/$2.out" >&2
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
        print t "\t" k "\t" ln
      }' "$log"
  done | LC_ALL=C sort -u >"$OUT/raw-hits.tsv"
  while IFS= read -r raw; do # resolve each distinct traced path once
    dir=$(cd "$(dirname "$raw")" 2>/dev/null && pwd -P) || continue
    [[ $dir/ == "$ROOT"/* ]] && rel_of[$raw]="${dir#"$ROOT"/}/$(basename "$raw")"
  done < <(cut -f2 "$OUT/raw-hits.tsv" | LC_ALL=C sort -u)
  while IFS=$'\t' read -r t raw ln; do
    if [[ -n ${rel_of[$raw]:-} ]]; then printf '%s\t%s\t%s\n' "$t" "${rel_of[$raw]}" "$ln"; fi
  done <"$OUT/raw-hits.tsv" | LC_ALL=C sort -u >"$OUT/hits.tsv"
}

floor_of() { awk -F'\t' -v p="$1" '$1 == p { print $2 }' "$FLOORS" 2>/dev/null || true; }

report() { # <update: 0|1>; prints the table, rewrites floors on update, returns 1 on a missing or low floor
  local update=$1 f exec_n hit_n now floor total_exec=0 total_hit=0 bad=0 invalid=0 status
  local -a rows=()
  printf '%-8s %9s %6s %6s  %s\n' status lines pct floor file
  while IFS= read -r f; do
    exec_n=$(awk -f "$HERE/coverage/executable.awk" "$ROOT/$f" | LC_ALL=C sort -u >"$OUT/exec" && wc -l <"$OUT/exec")
    awk -F'\t' -v p="$f" '$2 == p { print $3 }' "$OUT/hits.tsv" | LC_ALL=C sort -u >"$OUT/hit"
    hit_n=$(LC_ALL=C comm -12 <(LC_ALL=C sort "$OUT/exec") <(LC_ALL=C sort "$OUT/hit") | wc -l)
    exec_n=$((exec_n)); hit_n=$((hit_n))
    total_exec=$((total_exec + exec_n)); total_hit=$((total_hit + hit_n))
    now=$((exec_n == 0 ? 1000 : hit_n * 1000 / exec_n))
    floor=$(floor_of "$f")
    check "$f" "$now" "$floor" || bad=1
    [[ $status == BAD ]] && invalid=1
    printf '%-8s %4d/%-4d %6s %6s  %s\n' "$status" "$hit_n" "$exec_n" "$(pct "$now")" "${floor:--}" "$f"
    rows+=("$f"$'\t'"$(pct "$(newfloor "$now" "$floor")")")
  done < <(measured)
  now=$((total_exec == 0 ? 1000 : total_hit * 1000 / total_exec))
  floor=$(floor_of TOTAL)
  check TOTAL "$now" "$floor" || bad=1
  [[ $status == BAD ]] && invalid=1
  printf '%-8s %4d/%-4d %6s %6s  %s\n' "$status" "$total_hit" "$total_exec" "$(pct "$now")" "${floor:--}" TOTAL
  rows+=("TOTAL"$'\t'"$(pct "$(newfloor "$now" "$floor")")")
  if ((update && !invalid)); then printf '%s\n' "${rows[@]}" >"$FLOORS"; fi
  return $bad
}

check() { # <file> <now, tenths> <floor or empty>; sets status
  if [[ -z $3 ]]; then
    status="NO FLOOR"; ((update)) && return 0; return 1
  fi
  local floor_tenths
  floor_tenths=$(tenths "$3") || { status="BAD"; return 1; }
  if (($2 < floor_tenths)); then status="LOW"; return 1; fi
  status="ok"
}

newfloor() { # <now> <floor>: the higher of the two, in tenths
  local now=$1 floor_tenths
  if floor_tenths=$(tenths "${2:-}") && ((floor_tenths > now)); then now=$floor_tenths; fi
  echo "$now"
}

moved_to() { # <path>: a file in the repo with the same name, preferring one with a floor; fails if git cannot list the repo
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
  local path old new new_tenths old_tenths moved bad=0 base_total=0
  while IFS=$'\t' read -r path old || [[ -n $path ]]; do
    [[ -n $path ]] || continue
    [[ $path == TOTAL ]] && base_total=1
    new=$(floor_of "$path")
    if [[ -z $new && $path != TOTAL && ! -e $ROOT/$path ]]; then # a moved file keeps its name
      moved=$(moved_to "$path") || { echo "cannot list the repo's files to find $path"; bad=1; continue; }
      [[ -n $moved ]] || continue # deleted, so its floor may go
      new=$(floor_of "$moved"); path="$path -> $moved"
    fi
    if [[ -z $new ]]; then echo "floor removed: $path (was $old)"; bad=1; continue; fi
    if ! new_tenths=$(tenths "$new") || ! old_tenths=$(tenths "$old"); then
      echo "floor invalid: $path"; bad=1
    elif ((new_tenths < old_tenths)); then
      echo "floor lowered: $path $old -> $new"; bad=1
    fi
  done <"$1"
  # An empty base, such as a failed git show, would otherwise compare nothing and pass.
  if ((!base_total)); then echo "base has no TOTAL floor: $1"; bad=1; fi
  return $bad
}

case ${1:-} in
  --lines) awk -f "$HERE/coverage/executable.awk" "${2:?--lines needs a file}" ;;
  --ratchet) ratchet "${2:?--ratchet needs the base floor file}" ;;
  --update | "")
    update=0; [[ ${1:-} == --update ]] && update=1
    run_suites || exit 1
    hits
    report "$update"
    ;;
  *) die "unknown option: $1" ;;
esac
