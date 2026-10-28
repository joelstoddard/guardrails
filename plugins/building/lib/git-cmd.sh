#!/usr/bin/env bash
# git-cmd.sh — decide whether a shell command line runs `git <subcommand>` as its
# command, rather than merely mentioning it in an argument. Substring matching was
# wrong in both directions; see docs/design/git-command-parsing.md.
#
# Usage: _guardrails_invokes_git      "<cmdline>" <subcommand>        → rc 0 if run here, 2 if only on another host or
#                                                                       in a container, else 1.
#        _guardrails_git_effective_cwd "<cmdline>" <subcommand> <cwd> → prints the cwd git
#                                                                       will actually run in.
#        _guardrails_git_targets       "<cmdline>" <subcommand> <cwd> → the same, as "local: <dir>", and
#                                                                       "remote: <dir>" for one run elsewhere.
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
  local cmdline="$1" want="$2" depth="${3:-0}" remote="${4:-0}" carried per_line rc
  [ "$depth" -gt 4 ] && return 1
  carried="$(_guardrails_split_segments "$cmdline")"
  per_line="$(_GUARDRAILS_SPLIT_PER_LINE=1 _guardrails_split_segments "$cmdline")"
  _guardrails_git_in_segments "$carried"; rc=$?
  # Where the two splits agree, as they mostly do, one is read: both would double the work at each level. The per-line
  # split's lines are read by its own rule for a here-string, whose word it drops (#152).
  if [ "$rc" != 0 ] && [ "$per_line" != "$carried" ]; then
    _GUARDRAILS_SPLIT_PER_LINE=1 _guardrails_git_in_segments "$per_line"
    case "$?" in 0) rc=0 ;; 2) rc=2 ;; esac
  fi
  return "$rc"
}

# _guardrails_git_in_segments <segments> → rc 0 if one of them runs git with the caller's want, at the caller's depth,
# here, and 2 if one runs it only where the caller's remote, or a wrapper such as docker exec, sends it.
_guardrails_git_in_segments() {
  local seg i r rc=1
  local -a toks
  while IFS= read -r seg; do
    read -r -a toks <<<"$seg" || continue
    _guardrails_command_at; i="$_GUARDRAILS_CMD_AT"
    r="$remote"; [ "$_GUARDRAILS_CMD_WRAPPED" = 0 ] || [ "$_GUARDRAILS_CMD_REMOTE" = 0 ] || r=1
    case "$_GUARDRAILS_CMD" in
      git)
        _guardrails_git_skip_globals "$((i + 1))" "${toks[@]}"
        [ "$_GUARDRAILS_GIT_SUB" = "$want" ] && { [ "$r" = 1 ] || return 0; rc=2; }
        ;;
      *sh | eval)
        # A payload is split both ways again, whichever split it came from. ssh's runs on another host.
        [ "$_GUARDRAILS_CMD" != ssh ] || r=1
        _guardrails_shell_payload "$seg" || continue
        _GUARDRAILS_SPLIT_PER_LINE='' _guardrails_invokes_git "$_GUARDRAILS_PAYLOAD" "$want" "$((depth + 1))" "$r"
        case "$?" in 0) return 0 ;; 2) rc=2 ;; esac ;;
    esac
  done <<<"$1"
  return "$rc"
}

# Print the working directory in effect when each `git <subcommand>` runs, starting from <cwd>.
# Honours both `cd <path> &&` and cumulative `git -C <path>`, walked in order so they
# compose. Why this matters: docs/design/git-command-parsing.md.
#
# Usage: _guardrails_git_effective_cwd "<command line>" <subcommand> "<starting cwd>"
#        → one line for each directory a matching command runs in here, in either split, so a guard can judge them all;
#          with none, the directory each split ends in.
_guardrails_git_effective_cwd() {
  local line any=""
  local -A seen
  local -a ends=()
  while IFS= read -r line; do
    case "$line" in local:*) any=1 ;; end:*) ends+=("${line#* }"); continue ;; *) continue ;; esac
    [ -n "${seen[$line]+x}" ] || { seen[$line]=1; printf '%s\n' "${line#* }"; }
  done < <(_guardrails_git_walks "$@")
  [ -z "$any" ] || return 0
  for line in "${ends[@]}"; do [ -n "${seen[$line]+x}" ] || { seen[$line]=1; printf '%s\n' "$line"; }; done
}

# _guardrails_git_targets "<command line>" <subcommand> "<starting cwd>" → a line "local: <dir>" for each directory a
# matching command runs in here, and "remote: <dir>" for one run on another host or in a container, where a guard
# cannot judge its repo, from either split, each once; with none, "local: <dir>" for the directory each split ends in.
_guardrails_git_targets() {
  local line any=""
  local -A seen
  local -a ends=()
  while IFS= read -r line; do
    case "$line" in end:*) ends+=("local:${line#end:}"); continue ;; esac
    any=1; [ -n "${seen[$line]+x}" ] || { seen[$line]=1; printf '%s\n' "$line"; }
  done < <(_guardrails_git_walks "$@")
  [ -z "$any" ] || return 0
  for line in "${ends[@]}"; do [ -n "${seen[$line]+x}" ] || { seen[$line]=1; printf '%s\n' "$line"; }; done
}

# _guardrails_git_walks → the walk of each split, the carried and the per-line.
_guardrails_git_walks() {
  _guardrails_git_walk_cwd "$@"
  _GUARDRAILS_SPLIT_PER_LINE=1 _guardrails_git_walk_cwd "$@"
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

# Prints a line "local: <dir>" for each matching git command, or "remote: <dir>" where [remote] or a wrapper sends it
# elsewhere, then "end: <dir>", the directory in effect at the end.
# The carried split tags where each segment runs, so a substitution's commands are judged where it runs, before the
# command that holds it, in a child shell of its own (#114). See docs/design/git-command-parsing.md
_guardrails_git_walk_cwd() {
  local cmdline="$1" want="$2" top="$3" depth="${4:-0}" remote="${5:-0}" segs j k n=0 tg key cur id par host nop rem away
  local -a lines=() plain=() after=() at=()
  local -A scur curat later srem remat awayat
  [ "$depth" -gt 4 ] && { printf 'end: %s\n' "$top"; return; }
  if [ "${_GUARDRAILS_SPLIT_PER_LINE:-}" = 1 ]; then
    segs="$(_guardrails_split_awk 0 "$cmdline")"; [ -z "$segs" ] || mapfile -t plain <<<"$segs"
  else
    # Where quotes never close, every line is also read on its own, untagged, after the tagged lines.
    segs="$(_guardrails_split_awk 1 "$cmdline" 0 1)" || mapfile -t plain < <(_guardrails_split_awk 0 "$cmdline" 1)
    [ -z "$segs" ] || mapfile -t lines <<<"$segs"
  fi
  # after[j] is the operator after the segment tagged at j, before the next one in its scope that is not a piece. at
  # holds where the tags are, as an O tag has no segment after it.
  for ((j = 0; j < ${#lines[@]}; j++)); do case "${lines[$j]}" in O*) ;; *) at+=("$j"); j=$((j + 1)) ;; esac; done
  for ((k = ${#at[@]} - 1; k >= 0; k--)); do
    j="${at[$k]}"; tg="${lines[$j]}"
    key="${tg:0:1}"; case "$tg" in B*) key="b${tg#B?? }" ;; S*) key="s${tg#S?}" ;; esac
    after[j]="${later[$key]:-;}"
    case "$tg" in [TB]?1*) ;; *) later[$key]="${tg:1:1}" ;; esac
  done
  j=0
  while [ "$j" -lt "${#lines[@]}" ]; do
    tg="${lines[$j]}"; nop="${after[$j]:-;}"; j=$((j + 1)); key=t; cur="$top"; rem="$remote"
    case "$tg" in
      T*) ;;
      # A shell's heredoc is a script of its own, run where the line that opened it stands, and elsewhere if that line's
      # command is ssh's, or runs in a container.
      B*)
        host="${tg#B?? }"; key="b$host"
        [ -n "${scur[$key]+x}" ] || { scur[$key]="${curat[$host]-$top}"; srem[$key]="${awayat[$host]:-$remote}"; }
        cur="${scur[$key]}"; rem="${srem[$key]}" ;;
      O*)
        id="${tg#O}"; par="${id#* }"; host="${par#* }"; id="${id%% *}"; par="${par%% *}"
        if [ "$par" = 0 ]; then
          scur[s$id]="${curat[$host]-$top}"; srem[s$id]="${remat[$host]:-$remote}"
        else
          scur[s$id]="${scur[s$par]-$top}"; srem[s$id]="${srem[s$par]:-$remote}"
        fi
        continue ;;
      *) key="s${tg#S?}"; cur="${scur[$key]-$top}"; rem="${srem[$key]:-$remote}" ;;
    esac
    case "$tg" in
      # A piece of a substitution cut at an operator is read whole in the substitution's own segments.
      [TB]?1*) curat[$n]="$cur"; remat[$n]="$rem"; n=$((n + 1)); j=$((j + 1)); continue ;;
      [TB]*) curat[$n]="$cur"; remat[$n]="$rem" ;;
    esac
    away="$rem"; _guardrails_git_walk_seg "${lines[$j]:-}"; j=$((j + 1))
    case "$tg" in [TB]*) awayat[$n]="$away"; n=$((n + 1)) ;; esac
    if [ "$key" = t ]; then top="$cur"; else scur[$key]="$cur"; fi
  done
  # An untagged line shows no operator, so it is read as after a ;, as before.
  cur="$top"; nop=";"; rem="$remote"
  for j in "${!plain[@]}"; do away="$rem"; _guardrails_git_walk_seg "${plain[$j]}"; done
  printf 'end: %s\n' "$cur"
}

# _guardrails_git_walk_seg <segment> → prints a record for a matching git command in it, and moves the caller's cur
# where a cd or eval moves it. Reads the caller's want and depth, nop, the operator after the segment, and rem, 1 where
# the segment runs elsewhere, and sets the caller's away to 1 where its command does.
_guardrails_git_walk_seg() {
  local seg="$1" i k d w wrapped line
  local -a toks
  read -r -a toks <<<"$seg" || return
  _guardrails_command_at; i="$_GUARDRAILS_CMD_AT"; wrapped="$_GUARDRAILS_CMD_WRAPPED"
  # A wrapper such as env -C runs its command in another directory (#112), and one such as docker exec elsewhere.
  d="$cur"; [ "$wrapped" = 0 ] || { _guardrails_git_resolve "${_GUARDRAILS_CMD_DIRS[@]}"; [ "$_GUARDRAILS_CMD_REMOTE" = 0 ] || away=1; }
  [ "$_GUARDRAILS_CMD" != ssh ] || away=1
  case "$_GUARDRAILS_CMD" in
    cd)
      # A cd in a subshell does not last and one after a keyword may not run, so following either could miss a commit.
      # Nor does one piped into the next command, as each command of a pipeline but the last runs in a subshell (#115).
      [ "$wrapped" = 0 ] && [ "$nop" != "|" ] || return
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
        if [ "$away" = 1 ]; then printf 'remote: %s\n' "$d"; else printf 'local: %s\n' "$d"; fi
      fi
      ;;
    *sh | eval)
      # A payload's commands are judged where they run; only eval's cd outlives it, as sh -c runs in a child shell.
      _guardrails_shell_payload "$seg" || return
      while IFS= read -r line; do
        case "$line" in end:*) d="${line#end: }" ;; *) printf '%s\n' "$line" ;; esac
      done < <(_guardrails_git_walk_cwd "$_GUARDRAILS_PAYLOAD" "$want" "$d" "$((depth + 1))" "$away")
      [ "$_GUARDRAILS_CMD" = eval ] && [ "$wrapped" = 0 ] && [ "$nop" != "|" ] && cur="$d"
      ;;
  esac
}
