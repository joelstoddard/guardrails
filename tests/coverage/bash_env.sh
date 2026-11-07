# shellcheck shell=bash
# Read by every non-interactive bash through BASH_ENV: traces each executed line as file:line to $COV_LOG.
# See docs/design/coverage.md
[[ -n ${COV_LOG:-} ]] || return 0
# BASH_XTRACEFD and {fd} need bash 4.1; an older bash runs untraced, so its lines show as uncovered.
((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 1))) || return 0
if [[ -n ${COV_AWK:-} ]]; then
  # A plugin file's awk call also runs under gawk's profiler, so coverage.sh can count the statements of its program.
  __cov_awk_shim="${BASH_SOURCE[0]%/*}/awk_shim.sh"
  awk() {
    [[ ${BASH_SOURCE[1]:-} == *plugins/* ]] || { command awk "$@"; return; }
    # Untraced, as the trace already holds the call; xtrace only writes to the log, so turning it back on changes nothing.
    set +x
    BASH_ENV='' COV_LOG='' command bash "$__cov_awk_shim" "${BASH_SOURCE[1]}" "$@"
    set -- "$?"; set -x; return "$1"
  }
fi
exec {__cov_fd}>>"$COV_LOG"
BASH_XTRACEFD=$__cov_fd
PS4='+${BASH_SOURCE[0]}:${LINENO}: '
set -x
