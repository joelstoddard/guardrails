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
# A guard that sources this one learns so, and fails closed, if the splitter does not load.
. "$_GUARDRAILS_GIT_CMD_DIR/shell-split.sh" || return

# Git global options that consume a following, separate argument.
_guardrails_git_opt_takes_value() {
  case "$1" in
    -C | -c | --exec-path | --git-dir | --work-tree | --namespace | --super-prefix | \
      --config-env | --attr-source) return 0 ;;
    *) return 1 ;;
  esac
}

# _guardrails_git_skip_globals <index> <words> → sets _GUARDRAILS_GIT_SUB to the subcommand after git's global options,
# and _GUARDRAILS_GIT_DIRS to the -C directories in order. Variables, as a subshell per git command is slow.
_guardrails_git_skip_globals() {
  local i="$1" w opt="" k; shift
  local -a toks=("$@")
  _GUARDRAILS_GIT_SUB=""; _GUARDRAILS_GIT_DIRS=()
  while [ "$i" -lt "${#toks[@]}" ]; do
    w="${toks[$i]}"
    # The shell takes out redirects and drops quotes before git reads its words, as for the command word (#131).
    case "$w" in *[\<\>]*) _guardrails_skip_redirect && continue ;; esac
    case "$w" in *[\"\'\\]*) _guardrails_unquote ;; esac
    i=$((i + 1))
    # An option that takes a value, such as -C /x, takes the next word that is not a redirect: one shell word, though a
    # quote or an escaped blank in it spans several words of the split (#150).
    if [ -n "$opt" ]; then
      k=$((i - 1)); w="${toks[$k]}"; _guardrails_dir_word
      [ "$opt" != -C ] || _GUARDRAILS_GIT_DIRS+=("$w"); opt=""; continue
    fi
    case "$w" in
      --*=*) ;;                                                  # --git-dir=/x
      -*) _guardrails_git_opt_takes_value "$w" && opt="$w" ;;    # -C /x, --no-pager
      *)
        # git gets a quoted argument whole, so a subcommand read from one piece of it is left as written, as before.
        _GUARDRAILS_GIT_SUB="$w"; w="${toks[$((i - 1))]}"
        case "$w" in *[\"\'\\]*) _guardrails_whole_word || _GUARDRAILS_GIT_SUB="$w" ;; esac
        break ;;
    esac
  done
}

_guardrails_invokes_git() {
  local cmdline="$1" want="$2" depth="${3:-0}" carried per_line
  [ "$depth" -gt 4 ] && return 1
  carried="$(_guardrails_split_segments "$cmdline")"
  per_line="$(_GUARDRAILS_SPLIT_PER_LINE=1 _guardrails_split_segments "$cmdline")"
  _guardrails_git_in_segments "$carried" && return 0
  # Where the two splits agree, as they mostly do, one is read: both would double the work at each level. The per-line
  # split's lines are read by its own rule for a here-string, whose word it drops (#152).
  [ "$per_line" != "$carried" ] && _GUARDRAILS_SPLIT_PER_LINE=1 _guardrails_git_in_segments "$per_line"
}

# _guardrails_git_in_segments <segments> → rc 0 if one of them runs git with the caller's want, at the caller's depth.
_guardrails_git_in_segments() {
  local seg i
  local -a toks
  while IFS= read -r seg; do
    read -r -a toks <<<"$seg" || continue
    _guardrails_command_at; i="$_GUARDRAILS_CMD_AT"
    case "$_GUARDRAILS_CMD" in
      git)
        _guardrails_git_skip_globals "$((i + 1))" "${toks[@]}"
        [ "$_GUARDRAILS_GIT_SUB" = "$want" ] && return 0
        ;;
      *sh | eval)
        # A payload is split both ways again, whichever split it came from.
        _guardrails_shell_payload "$seg" &&
          _GUARDRAILS_SPLIT_PER_LINE='' _guardrails_invokes_git "$_GUARDRAILS_PAYLOAD" "$want" "$((depth + 1))" && return 0 ;;
    esac
  done <<<"$1"
  return 1
}

# Print the working directory in effect when each `git <subcommand>` runs, starting from <cwd>.
# Honours both `cd <path> &&` and cumulative `git -C <path>`, walked in order so they
# compose. Why this matters: docs/design/git-command-parsing.md.
#
# Usage: _guardrails_git_effective_cwd "<command line>" <subcommand> "<starting cwd>"
#        → one line for each directory a matching command runs in, in either split, so a guard can judge them all; with
#          none, the directory each split ends in.
_guardrails_git_effective_cwd() {
  local carried per_line line any=""
  local -A seen
  carried="$(_guardrails_git_walk_cwd "$@")"
  per_line="$(_GUARDRAILS_SPLIT_PER_LINE=1 _guardrails_git_walk_cwd "$@")"
  while IFS= read -r line; do
    case "$line" in local:*) any=1 ;; *) continue ;; esac
    [ -n "${seen[$line]+x}" ] || { seen[$line]=1; printf '%s\n' "${line#* }"; }
  done <<<"$carried"$'\n'"$per_line"
  [ -z "$any" ] || return 0
  while IFS= read -r line; do
    [ -n "${seen[$line]+x}" ] || { seen[$line]=1; printf '%s\n' "${line#* }"; }
  done <<<"$carried"$'\n'"$per_line"
}

# _guardrails_git_resolve <dir>... → moves the caller's d to each directory in turn, each relative to the last. Joined at
# once from the last absolute one, as appending one at a time is quadratic in their number.
_guardrails_git_resolve() {
  local k=$# w
  local -a rel=()
  while [ "$k" -gt 0 ]; do case "${!k}" in /*) break ;; esac; k=$((k - 1)); done
  [ "$k" = 0 ] || { d="${!k}"; shift "$k"; }
  for w in "$@"; do [ -z "$w" ] || rel+=("$w"); done
  [ "${#rel[@]}" = 0 ] || { local IFS=/; d="$d/${rel[*]}"; }
}

# Prints a line "local: <dir>" for each matching git command, then "end: <dir>", the directory in effect at the end.
_guardrails_git_walk_cwd() {
  local cmdline="$1" want="$2" cur="$3" depth="${4:-0}" seg i k d w wrapped line
  local -a toks
  [ "$depth" -gt 4 ] && { printf 'end: %s\n' "$cur"; return; }
  while IFS= read -r seg; do
    read -r -a toks <<<"$seg" || continue
    _guardrails_command_at; i="$_GUARDRAILS_CMD_AT"; wrapped="$_GUARDRAILS_CMD_WRAPPED"
    # A wrapper such as env -C runs its command in another directory (#112).
    d="$cur"; [ "$wrapped" = 0 ] || _guardrails_git_resolve "${_GUARDRAILS_CMD_DIRS[@]}"
    case "$_GUARDRAILS_CMD" in
      cd)
        # A cd in a subshell does not last and one after a keyword may not run, so following either could miss a commit.
        [ "$wrapped" = 0 ] || continue
        # Its options, such as -P, come before its directory, and -- ends them.
        for ((k = i + 1; k < ${#toks[@]}; k++)); do case "${toks[$k]}" in --) k=$((k + 1)); break ;; -?*) ;; *) break ;; esac; done
        i=$((k + 1)); w="${toks[$k]:-}"
        _guardrails_dir_word
        # `cd` alone (home) and `cd -` (previous) are not worth guessing at; leave cur be.
        case "$w" in
          '' | '-') ;;
          /*) cur="$w" ;;
          *) cur="$cur/$w" ;;
        esac
        ;;
      git)
        _guardrails_git_skip_globals "$((i + 1))" "${toks[@]}"
        if [ "$_GUARDRAILS_GIT_SUB" = "$want" ]; then
          _guardrails_git_resolve "${_GUARDRAILS_GIT_DIRS[@]}"
          printf 'local: %s\n' "$d"
        fi
        ;;
      *sh | eval)
        # A payload's commands are judged where they run; only eval's cd outlives it, as sh -c runs in a child shell.
        _guardrails_shell_payload "$seg" || continue
        while IFS= read -r line; do
          case "$line" in end:*) d="${line#end: }" ;; *) printf '%s\n' "$line" ;; esac
        done < <(_guardrails_git_walk_cwd "$_GUARDRAILS_PAYLOAD" "$want" "$d" "$((depth + 1))")
        [ "$_GUARDRAILS_CMD" = eval ] && [ "$wrapped" = 0 ] && cur="$d"
        ;;
    esac
  done < <(_guardrails_split_segments "$cmdline")
  printf 'end: %s\n' "$cur"
}
