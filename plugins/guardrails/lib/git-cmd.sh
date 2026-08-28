#!/usr/bin/env bash
# git-cmd.sh — decide whether a shell command line runs `git <subcommand>` as its
# command, rather than merely mentioning it in an argument. Substring matching was
# wrong in both directions; see docs/git-command-parsing.md.
#
# Usage: _guardrails_invokes_git      "<cmdline>" <subcommand>        → rc 0 if run, else 1.
#        _guardrails_git_effective_cwd "<cmdline>" <subcommand> <cwd> → prints the cwd git
#                                                                       will actually run in.

_GUARDRAILS_GIT_CMD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_GUARDRAILS_GIT_CMD_DIR/shell-split.sh"

# Git global options that consume a following, separate argument.
_guardrails_git_opt_takes_value() {
  case "$1" in
    -C | -c | --exec-path | --git-dir | --work-tree | --namespace | --super-prefix | \
      --config-env | --attr-source) return 0 ;;
    *) return 1 ;;
  esac
}

# Advance an index past git's global options. Echoes the new index.
_guardrails_git_skip_globals() {
  local i="$1"; shift
  local -a toks=("$@")
  while [ "$i" -lt "${#toks[@]}" ]; do
    case "${toks[$i]}" in
      --*=*) i=$((i + 1)) ;;                                     # --git-dir=/x
      -*) if _guardrails_git_opt_takes_value "${toks[$i]}"; then
            i=$((i + 2))                                         # -C /x
          else
            i=$((i + 1))                                         # --no-pager
          fi ;;
      *) break ;;
    esac
  done
  printf '%s' "$i"
}

_guardrails_invokes_git() {
  local cmdline="$1" want="$2" seg i
  local -a toks
  while IFS= read -r seg; do
    read -r -a toks <<<"$seg" || continue
    i=0
    # Skip leading environment assignments (NAME=value ...).
    while [ "$i" -lt "${#toks[@]}" ]; do
      case "${toks[$i]}" in
        [A-Za-z_]*=*) i=$((i + 1)) ;;
        *) break ;;
      esac
    done
    case "${toks[$i]:-}" in
      git | */git)
        i="$(_guardrails_git_skip_globals "$((i + 1))" "${toks[@]}")"
        [ "${toks[$i]:-}" = "$want" ] && return 0
        ;;
    esac
  done < <(_guardrails_split_segments "$cmdline")
  return 1
}

# Print the working directory in effect when `git <subcommand>` runs, starting from <cwd>.
# Honours both `cd <path> &&` and cumulative `git -C <path>`, walked in order so they
# compose. Why this matters: docs/git-command-parsing.md.
#
# Usage: _guardrails_git_effective_cwd "<command line>" <subcommand> "<starting cwd>"
_guardrails_git_effective_cwd() {
  local cmdline="$1" want="$2" cur="$3" seg i j k d v
  local -a toks
  while IFS= read -r seg; do
    read -r -a toks <<<"$seg" || continue
    i=0
    while [ "$i" -lt "${#toks[@]}" ]; do
      case "${toks[$i]}" in
        [A-Za-z_]*=*) i=$((i + 1)) ;;
        *) break ;;
      esac
    done
    case "${toks[$i]:-}" in
      cd)
        d="${toks[$((i + 1))]:-}"
        # `cd` alone (home) and `cd -` (previous) are not worth guessing at; leave cur be.
        case "$d" in
          '' | '-') ;;
          /*) cur="$d" ;;
          *) cur="$cur/$d" ;;
        esac
        ;;
      git | */git)
        j="$(_guardrails_git_skip_globals "$((i + 1))" "${toks[@]}")"
        if [ "${toks[$j]:-}" = "$want" ]; then
          k=$((i + 1))
          while [ "$k" -lt "$j" ]; do
            if [ "${toks[$k]}" = "-C" ]; then
              v="${toks[$((k + 1))]:-}"
              case "$v" in
                /*) cur="$v" ;;
                ?*) cur="$cur/$v" ;;
              esac
            fi
            k=$((k + 1))
          done
          printf '%s' "$cur"
          return 0
        fi
        ;;
    esac
  done < <(_guardrails_split_segments "$cmdline")
  printf '%s' "$cur"
}
