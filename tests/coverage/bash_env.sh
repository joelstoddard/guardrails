# shellcheck shell=bash
# Read by every non-interactive bash through BASH_ENV: traces each executed line as file:line to $COV_LOG.
# See docs/design/coverage.md
[[ -n ${COV_LOG:-} ]] || return 0
# BASH_XTRACEFD and {fd} need bash 4.1; an older bash runs untraced, so its lines show as uncovered.
((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 1))) || return 0
exec {__cov_fd}>>"$COV_LOG"
BASH_XTRACEFD=$__cov_fd
PS4='+${BASH_SOURCE[0]}:${LINENO}: '
set -x
