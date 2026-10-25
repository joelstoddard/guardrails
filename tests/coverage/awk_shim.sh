# shellcheck shell=bash
# Runs an awk call from a measured file twice, at once: under gawk's profiler for coverage.sh, and as called, whose
# output and status the caller gets. Usage: bash awk_shim.sh CALLER AWK-ARGUMENT... See docs/design/coverage.md
run=$COV_AWK/run.$$.$RANDOM
printf '%s\n' "$1" >"$run.caller" || exit 2
shift
args=("$@") i=0 program=1 files=0 dash=0
# POSIX awk's options come first, then the program unless -f named it, then the operands.
while ((i < ${#args[@]})); do
  case ${args[i]} in
    --) i=$((i + 1)); break ;;
    -f) program=0; i=$((i + 2)) ;;
    -v | -F) i=$((i + 2)) ;;
    -f?*) program=0; i=$((i + 1)) ;;
    -[vF]?*) i=$((i + 1)) ;;
    *) break ;;
  esac
done
for ((i += program; i < ${#args[@]}; i++)); do
  if [[ ${args[i]} =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then continue; fi # an assignment, not a file
  if [[ ${args[i]} == - ]]; then dash=1; continue; fi
  files=1
  # A pipe, such as a <( ) operand, can be read only once, so both runs read a copy of it.
  if [[ ! -f ${args[i]} ]] && cat -- "${args[i]}" >"$run.operand.$i" 2>/dev/null; then args[i]=$run.operand.$i; fi
done
if ((files && !dash)); then
  gawk --profile="$run.profile" "${args[@]}" </dev/null >/dev/null 2>&1 &
  awk "${args[@]}"
else
  cat >"$run.stdin"
  gawk --profile="$run.profile" "${args[@]}" <"$run.stdin" >/dev/null 2>&1 &
  awk "${args[@]}" <"$run.stdin"
fi
rc=$?
wait "$!"
exit "$rc"
