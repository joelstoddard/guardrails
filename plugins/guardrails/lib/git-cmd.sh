#!/usr/bin/env bash
# git-cmd.sh — decide whether a shell command line actually *invokes* `git <subcommand>`,
# rather than merely containing the string "git <subcommand>" somewhere (e.g. in a commit
# message, a PR body, or a grep pattern). Used by the guard/gate hooks so they act on real
# git invocations only.
#
# Handles: leading env assignments (`FOO=bar git ...`), an absolute path to git
# (`/usr/bin/git`), git's global options before the subcommand (`-C <path>`, `-c <k=v>`,
# `--git-dir`, `--no-pager`, …), and command chaining (`&&`, `||`, `;`, `|`, newlines).
#
# Known limitation: splitting on chain separators is not quote-aware, so a separator that
# appears *inside* a quoted argument (e.g. `echo "a; git commit b"`) can still be
# mis-read. This is far rarer than the plain-substring false positives it replaces, and a
# full shell parser is out of scope for a hook.
#
# Usage: _guardrails_invokes_git "<command line>" <subcommand>  → rc 0 if invoked, else 1.

# Does a single simple command invoke `git <want>`?
_guardrails_seg_is_git() { # $1=segment $2=wanted-subcommand
  local seg="$1" want="$2" t
  local -a toks=()
  read -r -a toks <<<"$seg" || return 1
  local i=0 n=${#toks[@]}

  # Skip leading environment assignments: NAME=value
  while [ "$i" -lt "$n" ]; do
    case "${toks[$i]}" in
      [A-Za-z_]*=*) i=$((i + 1)) ;;
      *) break ;;
    esac
  done

  # Next token must be git (bare or an absolute/relative path ending in /git).
  [ "$i" -lt "$n" ] || return 1
  case "${toks[$i]}" in
    git | */git) i=$((i + 1)) ;;
    *) return 1 ;;
  esac

  # Skip git's global options until the subcommand.
  while [ "$i" -lt "$n" ]; do
    case "${toks[$i]}" in
      # Options that consume a following, separate argument.
      -C | -c | --git-dir | --work-tree | --namespace | --super-prefix | --exec-path)
        i=$((i + 2)) ;;
      # Same options in --opt=value form, and other value-less global flags.
      --*=* | -p | --paginate | --no-pager | --bare | --no-replace-objects | \
      --literal-pathspecs | --glob-pathspecs | --noglob-pathspecs | \
      --icase-pathspecs | --no-optional-locks)
        i=$((i + 1)) ;;
      --) i=$((i + 1)); break ;;
      -*) i=$((i + 1)) ;; # any other global-ish flag
      *) break ;;
    esac
  done

  [ "$i" -lt "$n" ] || return 1
  [ "${toks[$i]}" = "$want" ]
}

_guardrails_invokes_git() { # $1=command line $2=wanted-subcommand
  local cmdline="$1" want="$2" seg
  # Break the command line into simple commands on && || ; | and newlines.
  while IFS= read -r seg; do
    [ -n "$seg" ] || continue
    _guardrails_seg_is_git "$seg" "$want" && return 0
  done < <(printf '%s\n' "$cmdline" | awk '{gsub(/&&|\|\||;|\|/, "\n")}1')
  return 1
}
