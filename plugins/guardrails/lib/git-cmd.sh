#!/usr/bin/env bash
# git-cmd.sh — decide whether a shell command line runs `git <subcommand>` as its command,
# rather than merely mentioning "git <subcommand>" in an argument (a commit message, a grep
# pattern, a PR body). That string-only match is what made a benign `gh pr create` whose
# body said "git commit" trip the guard.
#
# Deliberately minimal, in keeping with dumb tripwire hooks: for each chained simple command
# (split on && || ; | and newlines), skip leading VAR=value assignments, then require the
# command word to be git and the very next word to be the target subcommand. It does NOT
# look past git's global options, so `git -C <path> commit` is not matched. That bypass is
# acceptable — this is a fail-open guardrail, not a security boundary.
#
# Usage: _guardrails_invokes_git "<command line>" <subcommand>  → rc 0 if run, else 1.
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
      git | */git) [ "${toks[$((i + 1))]:-}" = "$want" ] && return 0 ;;
    esac
  done < <(printf '%s\n' "$cmdline" | awk '{gsub(/&&|\|\||;|\|/, "\n")}1')
  return 1
}
