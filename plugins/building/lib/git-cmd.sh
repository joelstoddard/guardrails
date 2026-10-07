#!/usr/bin/env bash
# git-cmd.sh — decide whether a shell command line runs `git <subcommand>` as its
# command, rather than merely mentioning it in an argument. Substring matching was
# wrong in both directions; see docs/design/git-command-parsing.md.
#
# Usage: _guardrails_invokes_git      "<cmdline>" <subcommand>        → rc 0 if run, else 1.
#        _guardrails_git_effective_cwd "<cmdline>" <subcommand> <cwd> → prints the cwd git
#                                                                       will actually run in.
#
# Both read the split that carries quotes across lines and the per-line split it replaced, so a
# quote the carried split misreads can never make a guard weaker than it was. Both also read the
# script a shell or eval runs from its command line, as publish-cmd.sh does.

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

# Advance an index past git's global options, into _GUARDRAILS_GIT_AT: a subshell per git command is slow.
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
  _GUARDRAILS_GIT_AT="$i"
}

_guardrails_invokes_git() {
  local cmdline="$1" want="$2" depth="${3:-0}" seg i carried per_line
  local -a toks
  [ "$depth" -gt 4 ] && return 1
  carried="$(_guardrails_split_segments "$cmdline")"
  per_line="$(_GUARDRAILS_SPLIT_PER_LINE=1 _guardrails_split_segments "$cmdline")"
  # Where the two splits agree, as they mostly do, one is read: both would double the work at each level.
  [ "$per_line" != "$carried" ] || per_line=""
  while IFS= read -r seg; do
    read -r -a toks <<<"$seg" || continue
    _guardrails_command_at; i="$_GUARDRAILS_CMD_AT"
    case "$_GUARDRAILS_CMD" in
      git)
        _guardrails_git_skip_globals "$((i + 1))" "${toks[@]}"; i="$_GUARDRAILS_GIT_AT"
        [ "${toks[$i]:-}" = "$want" ] && return 0
        ;;
      *sh | eval)
        _guardrails_shell_payload "$seg" &&
          _guardrails_invokes_git "$_GUARDRAILS_PAYLOAD" "$want" "$((depth + 1))" && return 0 ;;
    esac
  done <<<"$carried"$'\n'"$per_line"
  return 1
}

# Print the working directory in effect when `git <subcommand>` runs, starting from <cwd>.
# Honours both `cd <path> &&` and cumulative `git -C <path>`, walked in order so they
# compose. Why this matters: docs/design/git-command-parsing.md.
#
# Usage: _guardrails_git_effective_cwd "<command line>" <subcommand> "<starting cwd>"
#        → one line, or two when the two splits disagree, so a guard can judge both.
_guardrails_git_effective_cwd() {
  local carried per_line
  carried="$(_guardrails_git_walk_cwd "$@")"
  per_line="$(_GUARDRAILS_SPLIT_PER_LINE=1 _guardrails_git_walk_cwd "$@")"
  printf '%s\n' "$carried"
  [ "$per_line" = "$carried" ] || printf '%s\n' "$per_line"
}

# Prints the cwd, with rc 0 once the matching git command is reached and rc 1 if it never is.
_guardrails_git_walk_cwd() {
  local cmdline="$1" want="$2" cur="$3" depth="${4:-0}" seg i j k d v wrapped
  local -a toks
  [ "$depth" -gt 4 ] && { printf '%s' "$cur"; return 1; }
  while IFS= read -r seg; do
    read -r -a toks <<<"$seg" || continue
    _guardrails_command_at; i="$_GUARDRAILS_CMD_AT"; wrapped="$_GUARDRAILS_CMD_WRAPPED"
    case "$_GUARDRAILS_CMD" in
      cd)
        # A cd in a subshell does not last and one after a keyword may not run, so following either could miss a commit.
        [ "$wrapped" = 0 ] || continue
        d="${toks[$((i + 1))]:-}"
        # `cd` alone (home) and `cd -` (previous) are not worth guessing at; leave cur be.
        case "$d" in
          '' | '-') ;;
          /*) cur="$d" ;;
          *) cur="$cur/$d" ;;
        esac
        ;;
      git)
        _guardrails_git_skip_globals "$((i + 1))" "${toks[@]}"; j="$_GUARDRAILS_GIT_AT"
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
      *sh | eval)
        # A payload that runs the command says where; otherwise only eval's cd outlives it, as sh -c
        # runs in a child shell.
        _guardrails_shell_payload "$seg" || continue
        if d="$(_guardrails_git_walk_cwd "$_GUARDRAILS_PAYLOAD" "$want" "$cur" "$((depth + 1))")"; then
          printf '%s' "$d"
          return 0
        fi
        [ "${toks[$i]}" = eval ] && [ "$wrapped" = 0 ] && cur="$d"
        ;;
    esac
  done < <(_guardrails_split_segments "$cmdline")
  printf '%s' "$cur"
  return 1
}
