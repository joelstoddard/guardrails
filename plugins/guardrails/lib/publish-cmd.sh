#!/usr/bin/env bash
# publish-cmd.sh — decide whether a shell command line publishes content that would
# appear authored by the user.
#
# Deliberately vendor-neutral. Enumerating platforms (github, slack, linear…) fails
# the moment a new tool is adopted, and the rule being enforced is not "not these
# services" but "nothing posts as me". So this matches on the *shape* of an
# invocation instead: a publish verb in subcommand position of any tool, an HTTP
# write aimed at any remote host, or a mail transport.
#
# Usage: _guardrails_publishes_as_user "<cmdline>" → rc 0 and a reason on stdout if it
#                                                    publishes, rc 1 otherwise.

# Verbs that mean "make this visible to other people" wherever they appear as a
# subcommand. Matched exactly, so `publish-docs` and `notes` do not trip them.
_GUARDRAILS_PUBLISH_VERBS=' comment publish post send send-email reply review announce notify message msg tweet toot dm broadcast note '

# Tools that take arbitrary words as arguments; a verb here is data, not an action.
_GUARDRAILS_TEXT_TOOLS=' echo printf cat grep egrep fgrep rg ag sed awk ls find jq yq head tail wc sort uniq cut tr diff man which type test true false xargs tee '

# Mail transports publish as the user by definition.
_GUARDRAILS_MAIL_TOOLS=' mail mailx sendmail msmtp mutt neomutt s-nail '

_guardrails_is_write_verb() {
  case "$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')" in
    POST | PUT | PATCH | DELETE) return 0 ;;
    *) return 1 ;;
  esac
}

# `gh api` and friends default to GET, but a method or body flag promotes them to writes.
_guardrails_gh_api_writes() {
  local -a toks=("$@")
  local i=0
  while [ "$i" -lt "${#toks[@]}" ]; do
    case "${toks[$i]}" in
      -X | --method)
        _guardrails_is_write_verb "${toks[$((i + 1))]:-}" && return 0
        i=$((i + 2)); continue ;;
      -X*) _guardrails_is_write_verb "${toks[$i]#-X}" && return 0 ;;
      --method=*) _guardrails_is_write_verb "${toks[$i]#--method=}" && return 0 ;;
      -f | -F | --field | --raw-field | --input) return 0 ;;
      -f* | --field=* | --raw-field=* | --input=*) return 0 ;;
    esac
    i=$((i + 1))
  done
  return 1
}

_guardrails_http_has_body() {
  printf '%s' "$1" | grep -qE -- '(^|[[:space:]])(-X|--request)[[:space:]]*=?[[:space:]]*"?(POST|PUT|PATCH|DELETE)' && return 0
  printf '%s' "$1" | grep -qE -- '(^|[[:space:]])(-d|-F|--data|--data-raw|--data-binary|--data-urlencode|--json|--form|--upload-file|--post-data|--post-file)([[:space:]]|=)' && return 0
  return 1
}

# True when the command names a host that is not this machine. Loopback and .local
# are development, not publishing — that distinction is the deliberate hole here.
_guardrails_has_remote_target() {
  local seg="$1" url host
  while IFS= read -r url; do
    [ -n "$url" ] || continue
    host="${url#*://}"
    case "$host" in
      \[*) host="${host%%\]*}]" ;;
      *) host="${host%%/*}"; host="${host%%:*}" ;;
    esac
    case "$host" in
      localhost | localhost:* | 127.* | 0.0.0.0 | \[::1\] | ::1 | *.local | *.localhost) ;;
      *) return 0 ;;
    esac
  done < <(printf '%s' "$seg" | grep -oE '(https?://|(^|[[:space:]]))[A-Za-z0-9._-]+\.[A-Za-z]{2,}(:[0-9]+)?(/[^[:space:]"'"'"']*)?|https?://\[[^]]+\][^[:space:]]*|https?://localhost[^[:space:]]*|https?://127\.[^[:space:]]*' | sed 's/^[[:space:]]*//')
  return 1
}

_guardrails_publishes_as_user() {
  local cmdline="$1" depth="${2:-0}"
  [ "$depth" -gt 4 ] && return 1

  # The hatch is only meaningful when the human sets it in their own environment.
  # An assistant can prefix any command it writes, so an inline assignment is a bypass.
  case "$cmdline" in
    *ALLOW_PUBLISH_AS_ME=*)
      printf 'inline ALLOW_PUBLISH_AS_ME= assignment (the hatch is not self-grantable)'
      return 0 ;;
  esac

  local seg i inner base n
  local -a toks lead
  while IFS= read -r seg; do
    read -r -a toks <<<"$seg" || continue
    i=0
    while [ "$i" -lt "${#toks[@]}" ]; do
      case "${toks[$i]}" in
        [A-Za-z_]*=*) i=$((i + 1)) ;;
        *) break ;;
      esac
    done
    [ "$i" -lt "${#toks[@]}" ] || continue
    base="${toks[$i]##*/}"

    case "$base" in
      sh | bash | zsh | dash | ksh | eval)
        # Re-scan the quoted payload; `sh -c '<cmd>'` hides everything from prefix rules.
        inner="${seg#*-c }"
        [ "$inner" = "$seg" ] && inner="${seg#*eval }"
        inner="${inner#[\"\']}"; inner="${inner%[\"\']}"
        if [ -n "$inner" ] && [ "$inner" != "$seg" ]; then
          _guardrails_publishes_as_user "$inner" "$((depth + 1))" && return 0
        fi
        continue ;;
    esac

    case " $_GUARDRAILS_MAIL_TOOLS " in
      *" $base "*)
        printf '%s sends mail as you' "$base"
        return 0 ;;
    esac

    case "$base" in
      curl | wget | http | https | httpie | xh | xhs)
        # httpie takes the method as its first argument: `http POST url field=v`.
        if _guardrails_is_write_verb "${toks[$((i + 1))]:-}" ||
          _guardrails_http_has_body "$seg"; then
          if _guardrails_has_remote_target "$seg"; then
            printf 'HTTP write to a remote host'
            return 0
          fi
        fi
        continue ;;
    esac

    if [ "${toks[$((i + 1))]:-}" = "api" ] &&
      _guardrails_gh_api_writes "${toks[@]:$((i + 2))}"; then
      printf '%s api with a write method or body flag' "$base"
      return 0
    fi

    # A publish verb in subcommand position. Leading non-flag tokens only, so a verb
    # appearing in a message body or a flag value is data rather than an invocation.
    case " $_GUARDRAILS_TEXT_TOOLS " in
      *" $base "*) continue ;;
    esac
    lead=()
    n="$i"
    while [ "$n" -lt "${#toks[@]}" ] && [ "${#lead[@]}" -lt 4 ]; do
      case "${toks[$n]}" in
        -*) break ;;
        *) lead+=("${toks[$n]}") ;;
      esac
      n=$((n + 1))
    done
    # Opening a review request is fine unasked; opening a *ready* one is not, because
    # it notifies reviewers. Draft first, promotion by hand. Scan the whole segment so
    # the flag's position does not matter.
    case "${lead[1]:-}/${lead[2]:-}" in
      pr/create | mr/create | merge-request/create)
        # Spelled out in full only: -d is --draft in one forge CLI and --description
        # in another, so it is not proof of anything. Costs a prompt, never a leak.
        case " $seg " in
          *' --draft'* | *' --wip'*) ;;
          *)
            printf '%s %s create without --draft (drafts only; promoting is yours)' \
              "$base" "${lead[1]}"
            return 0 ;;
        esac ;;
    esac

    for n in 1 2 3; do
      [ "$n" -lt "${#lead[@]}" ] || break
      case "$_GUARDRAILS_PUBLISH_VERBS" in
        *" ${lead[$n]} "*)
          printf '%s %s publishes under your name' "$base" "${lead[$n]}"
          return 0 ;;
      esac
    done
  done < <(printf '%s\n' "$cmdline" | awk '{gsub(/&&|\|\||;|\|/, "\n")}1')
  return 1
}
