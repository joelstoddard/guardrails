#!/usr/bin/env bash
# publish-cmd.sh — decide whether a shell command line publishes content that would
# appear authored by the user.
#
# A list of platforms goes stale when a new tool is adopted, and the rule is
# "nothing posts as me", not "not these services". So this matches the shape of an
# invocation: a publish verb in subcommand position, an HTTP write to a remote
# host, or a mail transport.
#
# Usage: _guardrails_publishes_as_user "<cmdline>" → rc 0 and a reason on stdout if it
#                                                    publishes, rc 2 and a reason if it may,
#                                                    rc 1 otherwise.

_GUARDRAILS_PUBLISH_CMD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# A guard that sources this one learns so, and fails closed, if the splitter does not load.
. "$_GUARDRAILS_PUBLISH_CMD_DIR/shell-split.sh" || return

# Verbs that mean "make this visible to other people" wherever they appear as a
# subcommand. Matched exactly, so `publish-docs` and `notes` do not trip them.
_GUARDRAILS_PUBLISH_VERBS=' comment publish post send send-email reply review announce notify message msg tweet toot dm broadcast note '

# Tools that take arbitrary words as arguments; a verb here is data, not an action.
_GUARDRAILS_TEXT_TOOLS=' echo printf cat grep egrep fgrep rg ag sed awk ls find jq yq head tail wc sort uniq cut tr diff man which type test true false tee '

# Mail transports publish as the user by definition.
_GUARDRAILS_MAIL_TOOLS=' mail mailx sendmail msmtp mutt neomutt s-nail '

# Case patterns rather than tr, which forks; ſ is the one letter a locale uppercases to an ASCII S.
_guardrails_is_write_verb() {
  case "$1" in
    [Pp][Oo][Ss][Tt] | [Pp][Oo]ſ[Tt] | [Pp][Uu][Tt] | [Pp][Aa][Tt][Cc][Hh] | [Dd][Ee][Ll][Ee][Tt][Ee]) return 0 ;;
    *) return 1 ;;
  esac
}

# `gh api` and friends default to GET, but a method or body flag promotes them to writes. Reads the caller's toks from
# <index>, past redirects and with quotes dropped, as the shell takes them out (#146).
_guardrails_gh_api_writes() {
  local i="$1" w m=0
  while [ "$i" -lt "${#toks[@]}" ]; do
    w="${toks[$i]}"
    case "$w" in *[\<\>]*) _guardrails_skip_redirect && continue ;; esac
    case "$w" in *[\"\'\\]*) _guardrails_unquote ;; esac
    i=$((i + 1))
    if [ "$m" = 1 ]; then _guardrails_is_write_verb "$w" && return 0; m=0; continue; fi
    case "$w" in
      -X | --method) m=1 ;;
      -X*) _guardrails_is_write_verb "${w#-X}" && return 0 ;;
      --method=*) _guardrails_is_write_verb "${w#--method=}" && return 0 ;;
      -f | -F | --field | --raw-field | --input) return 0 ;;
      -f* | -F* | --field=* | --raw-field=* | --input=*) return 0 ;;
    esac
  done
  return 1
}

# How each client reads a cluster of short options: flags, then one that takes a value, attached or as the next word.
_GUARDRAILS_CURL_SHORT='^-[aqfGgI0k46jlLMnNZ#pJORSis231BvVh:]*([AbCcDdEeFHKmoPQrTtUuwXxYyz])(.*)$'
_GUARDRAILS_WGET_SHORT='^-[VhbdqvFcNS46xErkKmpHL]*([eoaiBtOTwQPUlARDIXn])(.*)$'
_GUARDRAILS_HTTPIE_SHORT='^-[jfxhmbvSdcqFI46k]*([aAopPs])(.*)$'
# An httpie or xh request item whose first separator sends data: =, :=, @, =@ or :=@, where == and : do not.
_GUARDRAILS_HTTPIE_DATA='^[^:=@;]*(=[^=]|=$|:=|@)'

# _guardrails_http_writes <client> <index> → rc 0 if the client sends a body or a write method, read from the caller's
# toks from <index> as the shell passes them: past redirects, with quotes dropped, and a quoted word whole. Sets
# _GUARDRAILS_HTTP_WORDS to the words that can name the host: all but redirects and the values of the options that
# never do, an output file, a header, a header dump or a cookie jar. Sets _GUARDRAILS_HTTP_ASK to why a write may go
# elsewhere than its URL reads: the URL comes from a variable or substitution, or curl sends it to another host. Sets
# _GUARDRAILS_HTTP_MAIL where curl sends mail: a mail recipient, or an SMTP URL.
_guardrails_http_writes() {
  local base="$1" i="$2" w v j k d re p=0 u=1 opts=1 rc=1
  local -a kept=("${toks[@]:0:i}")
  _GUARDRAILS_HTTP_ASK=""; _GUARDRAILS_HTTP_MAIL=""
  case "$base" in curl) re="$_GUARDRAILS_CURL_SHORT" ;; wget) re="$_GUARDRAILS_WGET_SHORT" ;; *) re="$_GUARDRAILS_HTTPIE_SHORT" ;; esac
  # A regex fails on text holding an invalid byte in a UTF-8 locale, on macOS even before the byte.
  case "${toks[*]}" in *[![:ascii:]]*) local LC_ALL=C ;; esac
  while [ "$i" -lt "${#toks[@]}" ]; do
    w="${toks[$i]}"
    case "$base$w" in curl[Ss][Mm][Tt][Pp]:* | curl[Ss][Mm][Tt][Pp][Ss]:*) _GUARDRAILS_HTTP_MAIL=1 ;; esac
    # Only a word that starts with -, a quote, $ or \ can be an option, with < or > a redirect, and with $ or ` a URL from
    # a variable or substitution. curl and wget read no other word here.
    case "$base$w" in curl[!-\"\'\$\\\<\>\`]* | wget[!-\"\'\$\\\<\>\`]*) kept+=("$w"); i=$((i + 1)); continue ;; esac
    # httpie and xh send what they read on stdin as the body.
    case "$w" in *[\<\>]*) _guardrails_skip_redirect && { case "$base/$w" in curl/* | wget/*) ;; */*\<*) rc=0 ;; esac; continue; } ;; esac
    j="$i"; i=$((i + 1)); d=""
    case "$w" in *[\"\'\\]*) _guardrails_unquote ;; esac
    case "$opts$w" in
      1--) opts="" ;;
      1--*)
        case "$base$w" in
          curl--data | curl--data-ascii | curl--data-binary | curl--data-raw | curl--data-urlencode | curl--json | \
            curl--form | curl--form-string | curl--upload-file | wget--post-data | wget--post-file | wget--body-data | \
            wget--body-file | http*--raw | xh*--raw)
            _guardrails_http_value; rc=0 ;;
          curl--data=* | curl--data-*=* | curl--json=* | curl--form=* | curl--form-string=* | curl--upload-file=* | \
            wget--post-*=* | wget--body-*=* | http*--raw=* | xh*--raw=*) rc=0 ;;
          curl--request | wget--method) _guardrails_http_value; _guardrails_is_write_verb "$v" && rc=0 ;;
          curl--request=* | wget--method=*) v="${w#--request=}"; _guardrails_is_write_verb "${v#--method=}" && rc=0 ;;
          wget--execute) _guardrails_http_value; _guardrails_wgetrc_writes && rc=0 ;;
          wget--execute=*) v="${w#--execute=}"; _guardrails_wgetrc_writes && rc=0 ;;
          curl--resolve | curl--connect-to) _guardrails_http_value; _GUARDRAILS_HTTP_ASK="a host that $w sends elsewhere" ;;
          curl--mail-rcpt) _guardrails_http_value; _GUARDRAILS_HTTP_MAIL=1; rc=0 ;;
          curl--mail-rcpt=* | curl--mail-rcpt-allowfails) _GUARDRAILS_HTTP_MAIL=1; rc=0 ;;
          curl--output | curl--dump-header | curl--cookie-jar | curl--header | wget--output-document | wget--header | \
            http*--output | xh*--output)
            _guardrails_http_value; d=1 ;;
          curl--output=* | curl--dump-header=* | curl--cookie-jar=* | curl--header=* | wget--output-document=* | \
            wget--header=* | http*--output=* | xh*--output=*) d=1 ;;
          # An option's value is not the URL, and httpie and xh count their arguments to tell the URL from the items.
          curl--user | curl--user-agent | curl--cookie | curl--referer | curl--write-out | curl--max-time | \
            curl--connect-timeout | curl--retry | curl--oauth2-bearer | curl--cert | curl--key | curl--cacert | \
            curl--variable | curl--proxy-user | curl--range | wget--user | wget--password | wget--user-agent | \
            wget--referer | wget--timeout | wget--tries | \
            http*--auth | http*--auth-type | http*--session | http*--session-read-only | http*--proxy | \
            http*--print | http*--history-print | http*--style | http*--pretty | http*--timeout | http*--verify | \
            http*--cert | http*--cert-key | http*--ssl | http*--default-scheme | xh*--auth | xh*--auth-type | \
            xh*--session | xh*--session-read-only | xh*--proxy | xh*--print | xh*--history-print | \
            xh*--style | xh*--pretty | xh*--timeout | xh*--verify | xh*--cert | xh*--cert-key | xh*--ssl | \
            xh*--default-scheme | xh*--bearer | xh*--resolve)
            _guardrails_http_value ;;
        esac ;;
      1-?*)
        # A failed match empties BASH_REMATCH, so a cluster of flags alone takes no value.
        [[ $w =~ $re ]]; v="${BASH_REMATCH[2]:-}"; w="${BASH_REMATCH[1]:-}"
        [ -z "$w" ] || [ -n "$v" ] || _guardrails_http_value
        case "$base$w" in
          curl[dFT]) rc=0 ;;
          curlX) _guardrails_is_write_verb "$v" && rc=0 ;;
          wgete) _guardrails_wgetrc_writes && rc=0 ;;
          curl[oDcH] | wgetO | http*o | xh*o) d=1 ;;
        esac ;;
      *)
        case "$base$w" in curl[Ss][Mm][Tt][Pp]:* | curl[Ss][Mm][Tt][Pp][Ss]:*) _GUARDRAILS_HTTP_MAIL=1 ;; esac
        # A URL from a variable or a substitution can name any host.
        case "${toks[$j]}" in \$[!\"\']* | \"\$* | \`* | \"\`*) v=1 ;; *) v="" ;; esac
        case "$base" in curl | wget) [ -z "$v" ] || _GUARDRAILS_HTTP_ASK="a URL from a variable" ;; *)
          # httpie and xh read their first argument as the method if it is letters only, then the URL, then the items.
          # A quoted argument of several words is one item.
          case "${toks[$j]}" in [\"\']?*[\"\']) ;; [\"\']*) _guardrails_skip_quoted "${toks[$j]}" ;; esac
          p=$((p + 1))
          if [ "$p" = 1 ] && [ "$i" = "$((j + 1))" ] && [[ $w =~ ^[A-Za-z]+$ ]]; then
            u=2; _guardrails_is_write_verb "$w" && rc=0
          elif [ "$p" = "$u" ]; then
            [ -z "$v" ] || _GUARDRAILS_HTTP_ASK="a URL from a variable"
          elif [[ ${toks[$j]} =~ $_GUARDRAILS_HTTPIE_DATA ]]; then
            rc=0
          fi ;;
        esac ;;
    esac
    # By index, as a slice of a bash array walks it from its start.
    [ -n "$d" ] || for ((k = j; k < i; k++)); do kept+=("${toks[$k]}"); done
  done
  _GUARDRAILS_HTTP_WORDS="${kept[*]}"
  return "$rc"
}

# _guardrails_http_value → the caller's v is an option's value: its next word past redirects, whole and unquoted.
_guardrails_http_value() {
  local w
  while w="${toks[$i]:-}"; case "$w" in *[\<\>]*) _guardrails_skip_redirect ;; *) false ;; esac; do :; done
  v="$w"; i=$((i + 1))
  case "$w" in *[\"\'\\]*) _guardrails_skip_quoted "$w"; _guardrails_unquote && v="$w" ;; esac
}

# _guardrails_wgetrc_writes → rc 0 if the caller's v, a wgetrc command, sends a body or sets a write method. wget reads
# a command's name in any case and without its _ and -, and a name too long to be one is cut.
_guardrails_wgetrc_writes() {
  local c="${v:0:64}"
  c="${c,,}"; c="${c//[_-]/}"
  case "$c" in
    postdata* | postfile* | bodydata* | bodyfile*) return 0 ;;
    method=*) _guardrails_is_write_verb "${c#method=}" ;;
    *) return 1 ;;
  esac
}

# _guardrails_host_class <host> [<var>] → rc 0 if the host is proven to be this machine, 1 if it is not, and 2 if it may
# not be: a name with no dot, a private address, or, given <var>, a host a variable or substitution can change.
# Loopback and .local are development, not publishing — that distinction is the deliberate hole here.
# See docs/design/url-hosts.md
_GUARDRAILS_LOOPBACK='^127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'
_GUARDRAILS_PUBLIC_NAME='^[A-Za-z0-9._-]+\.[A-Za-z]{2,}'
_GUARDRAILS_PRIVATE='^(10\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])|192\.168|169\.254)\.[0-9]{1,3}\.[0-9]{1,3}$|^\[[Ff][CcDd][0-9A-Fa-f]{2}:'
_guardrails_host_class() {
  local h="$1" l=""
  # A public name can start with 127., so only a dotted address is loopback (#128).
  case "$h" in
    localhost | 0.0.0.0 | \[::1\]) l=1 ;;
    *[!A-Za-z0-9._-]*) ;;
    *.local | *.localhost) l=1 ;;
    127.*) [[ $h =~ $_GUARDRAILS_LOOPBACK ]] && l=1 ;;
  esac
  [ -z "$l" ] || { [ -n "$2" ] && return 2; return 0; }
  # A public name is refused as before, whatever a variable after it adds.
  [[ $h =~ $_GUARDRAILS_PUBLIC_NAME ]] && return 1
  [ -z "$2" ] || return 2
  case "$h" in "" | *[!A-Za-z0-9_-]*) [[ $h =~ $_GUARDRAILS_PRIVATE ]] && return 2; return 1 ;; esac
  return 2
}

# _guardrails_has_remote_target <words> → rc 0 if they name a host that is not this machine, 2 if one may not be and
# none is known not to be, and 1 otherwise. See docs/design/url-hosts.md
_guardrails_has_remote_target() {
  local seg="$1" rest url host re n w s v j=0 rc=1 lead='^[[:space:]]*(.*)$' word='^[^[:space:]]*'
  # A variable or substitution before the path can make any host, an @ or a /.
  local variable='^/*[^/?#]*[$`]' scheme='^([Hh][Tt][Tt][Pp][Ss]?:|[A-Za-z][A-Za-z0-9+.-]*://)'
  # The host follows the slashes after the scheme, and the last @ before the first /, ? or #, as no client reaches a
  # host before it (#149).
  local authority='^/*([^/?#]*@)?(\[[^]]*\]|[^/?#:@]*)'
  # curl reads a URL's scheme in any case, and xh and httpie read a word that starts with http: or https: followed by any
  # number of slashes, none included, as a WHATWG parser does: http:evil.com is http://evil.com. curl uploads over other
  # schemes too, such as ftp:// and imap://, whose host is read the same way.
  local first='(^|[[:space:]])([Hh][Tt][Tt][Pp][Ss]?:|[A-Za-z][A-Za-z0-9+.-]*://)[^[:space:]]*|[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]/?#]*@[^[:space:]]*|[A-Za-z][A-Za-z0-9+.-]*://\[[^]]+\][^[:space:]]*|[A-Za-z][A-Za-z0-9+.-]*://localhost[^[:space:]]*|[A-Za-z][A-Za-z0-9+.-]*://127\.[^[:space:]]*|([A-Za-z][A-Za-z0-9+.-]*://|(^|[[:space:]]))[A-Za-z0-9._-]+\.[A-Za-z]{2,}(:[0-9]+)?(/[^[:space:]"'"'"']*)?|(^|[[:space:]])[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'
  local next='[[:space:]]([Hh][Tt][Tt][Pp][Ss]?:|[A-Za-z][A-Za-z0-9+.-]*://)[^[:space:]]*|[A-Za-z][A-Za-z0-9+.-]*://[^[:space:]/?#]*@[^[:space:]]*|[A-Za-z][A-Za-z0-9+.-]*://\[[^]]+\][^[:space:]]*|[A-Za-z][A-Za-z0-9+.-]*://localhost[^[:space:]]*|[A-Za-z][A-Za-z0-9+.-]*://127\.[^[:space:]]*|([A-Za-z][A-Za-z0-9+.-]*://|[[:space:]])[A-Za-z0-9._-]+\.[A-Za-z]{2,}(:[0-9]+)?(/[^[:space:]"'"'"']*)?|[[:space:]][0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'
  local -a toks
  # Quotes and backslashes can hide the dot or the :// of a URL.
  case "$seg" in *.* | *[Hh][Tt][Tt][Pp]:* | *[Hh][Tt][Tt][Pp][Ss]:* | *://* | *[\"\'\\]*) ;; *) return 1 ;; esac
  # Bytes: the shell splits words on ASCII blanks only, and dropping quotes is quadratic in a UTF-8 locale (#134).
  case "$seg" in *[![:ascii:]]* | *[\"\'\\]*) local LC_ALL=C ;; esac
  # The shell drops quotes, and the $ of $'' or $"", before curl reads a word (#148). A backslash can stay or make any
  # character, so a word with one is remote if it holds a URL or a $''.
  case "$seg" in
    *[\"\'\\]*)
      read -r -a toks <<<"$seg"
      for w in "${toks[@]}"; do
        case "$w" in
          *\\*)
            case "$w" in *\$\'*) return 0 ;; esac
            w="${w//\$[\"\']/}"; w="${w//[\"\'\\]/}"; [[ $w =~ $first ]] && return 0; toks[j]="$w" ;;
          *[\"\']*) w="${w//\$[\"\']/}"; toks[j]="${w//[\"\']/}" ;;
        esac
        j=$((j + 1))
      done
      seg="${toks[*]}" ;;
  esac
  # The URLs in turn, as grep -o finds them: leftmost, longest, each after the last, with ^ only at the start. Of
  # equal matches glibc takes the first alternative, so those that run to a blank come first, as they are the longest.
  rest="$seg"; re="$first"; n=0
  while [[ $rest =~ ($re)(.*)$ ]]; do
    # Each URL costs a regex over the rest of the segment, so past 32 of them it is read as remote.
    n=$((n + 1)); [ "$n" -le 32 ] || return 0
    url="${BASH_REMATCH[1]}"; rest="${BASH_REMATCH[${#BASH_REMATCH[@]} - 1]}"; re="$next"
    case "$url" in [[:space:]]*) [[ $url =~ $lead ]] && url="${BASH_REMATCH[1]}" ;; esac
    # Regexes and a guarded ${url#*://}, as ${host%%/*} and an unmatched ${url#*://} are quadratic. The host comes from
    # the URL's whole word, as a match can stop before an @ (#149), and ends at its first /, though a :// follows (#128).
    [[ $rest =~ $word ]]; host="$url${BASH_REMATCH[0]}"; s=""; v=""
    [[ $host =~ $scheme ]] && { host="${host#*:}"; s=1; }
    case "$host" in *[\$\`]*) [[ $host =~ $variable ]] && v=1 ;; esac
    [[ $host =~ $authority ]]; host="${BASH_REMATCH[2]}"
    _guardrails_host_class "$host" "$v"
    case $? in
      1) return 0 ;;
      # Of a word with no scheme, only a private address asks: any other host in one was refused before.
      2) [ -n "$s" ] || [ "$url" = "$host" ] || return 0; rc=2 ;;
    esac
  done
  return "$rc"
}

_guardrails_publishes_as_user() {
  local cmdline="$1" depth="${2:-0}"
  [ "$depth" -gt 4 ] && return 1
  # A payload's question is the whole command's, so every depth adds to one.
  [ "$depth" -gt 0 ] || _GUARDRAILS_PUBLISH_ASK=""

  # The hatch is only meaningful when the human sets it in their own environment.
  # An assistant can prefix any command it writes, so an inline assignment is a bypass.
  case "$cmdline" in
    *ALLOW_PUBLISH_AS_ME=*)
      printf 'inline ALLOW_PUBLISH_AS_ME= assignment (the hatch is not self-grantable)'
      return 0 ;;
  esac

  local seg i at base n w reason
  local -a toks lead piece
  while IFS= read -r seg; do
    read -r -a toks <<<"$seg" || continue
    _guardrails_command_at; i="$_GUARDRAILS_CMD_AT"; base="$_GUARDRAILS_CMD"
    [ "$i" -lt "${#toks[@]}" ] || continue

    case "$base" in
      sh | bash | zsh | dash | ksh | eval | su | script)
        # Re-scan the payload; `sh -c '<cmd>'` hides everything from prefix rules.
        if _guardrails_shell_payload "$seg"; then
          _guardrails_publishes_as_user "$_GUARDRAILS_PAYLOAD" "$((depth + 1))" && return 0
        fi
        continue ;;
      # ssh runs its command on another host, as you, so that is read too, as well as the words after ssh (#113).
      ssh) _guardrails_shell_payload "$seg" && _guardrails_publishes_as_user "$_GUARDRAILS_PAYLOAD" "$((depth + 1))" && return 0 ;;
    esac

    case " $_GUARDRAILS_MAIL_TOOLS " in
      *" $base "*)
        printf '%s sends mail as you' "$base"
        return 0 ;;
    esac

    # The command and the words after it before the first option, past redirects and with quotes dropped, as the command
    # reads them (#131, #146). An option is matched as written, so a quoted one stays a word, as it was before.
    at="$i"; lead=("$base"); piece=(); i=$((i + 1))
    while [ "$i" -lt "${#toks[@]}" ] && [ "${#lead[@]}" -lt 4 ]; do
      w="${toks[$i]}"
      case "$w" in -*) break ;; *[\<\>]*) _guardrails_skip_redirect && continue ;; esac
      case "$w" in *[\"\'\\]*) _guardrails_whole_word || piece[${#lead[@]}]="$w"; _guardrails_unquote ;; esac
      lead+=("$w")
      i=$((i + 1))
    done

    # A method or api read from one piece of a quoted argument of several words may not be the command's, as the shell
    # passes the argument whole, so it asks, as a verb read from one does.
    case "$base" in
      curl | wget | http | https | httpie | xh | xhs)
        # httpie takes the method as its first argument: `http POST url field=v`.
        if _guardrails_http_writes "$base" "$((at + 1))" || { _guardrails_is_write_verb "${lead[1]:-}" && [ -z "${piece[1]:-}" ]; }; then
          [ -z "$_GUARDRAILS_HTTP_MAIL" ] || { printf 'curl sends mail as you'; return 0; }
          _guardrails_has_remote_target "$_GUARDRAILS_HTTP_WORDS"
          case $? in
            0) printf 'HTTP write to a remote host'; return 0 ;;
            2) : "${_GUARDRAILS_PUBLISH_ASK:=HTTP write to a host not proven local, as a name with no dot, a private address or a variable}" ;;
            *) [ -z "$_GUARDRAILS_HTTP_ASK" ] || : "${_GUARDRAILS_PUBLISH_ASK:=HTTP write to $_GUARDRAILS_HTTP_ASK}" ;;
          esac
        elif _guardrails_is_write_verb "${lead[1]:-}" && _guardrails_has_remote_target "$_GUARDRAILS_HTTP_WORDS"; then
          : "${_GUARDRAILS_PUBLISH_ASK:=HTTP write to a remote host, read from ${piece[1]}, one piece of a quoted argument}"
        fi
        continue ;;
    esac

    if [ "${lead[1]:-}" = api ] && _guardrails_gh_api_writes "$((at + 1))"; then
      printf -v reason '%s api with a write method or body flag' "$base"
      [ -n "${piece[1]:-}" ] || { printf '%s' "$reason"; return 0; }
      : "${_GUARDRAILS_PUBLISH_ASK:=$reason, read from ${piece[1]}, one piece of a quoted argument}"
    fi

    # A publish verb in subcommand position. Leading non-flag tokens only, so a verb
    # appearing in a message body or a flag value is data rather than an invocation.
    case " $_GUARDRAILS_TEXT_TOOLS " in
      *" $base "*) continue ;;
    esac
    # Help as the first option publishes nothing (#78); a later -h could be another option's value, as in --title -h.
    case "${toks[$i]:-}" in --help | -h) continue ;; esac
    # A ready review request notifies reviewers, so only a draft is safe unasked.
    # Scan the whole segment, because the flag's position can change.
    case "${lead[1]:-}/${lead[2]:-}" in
      pr/create | mr/create | merge-request/create)
        # Spelled out in full only: -d is --draft in one forge CLI and --description
        # in another, so it is not proof of anything. Costs a prompt, never a leak.
        case " $seg " in
          *' --draft'* | *' --wip'*) ;;
          *)
            printf -v reason '%s %s create without --draft (drafts only; promoting is yours)' "$base" "${lead[1]}"
            [ -n "${piece[1]:-}${piece[2]:-}" ] || { printf '%s' "$reason"; return 0; }
            : "${_GUARDRAILS_PUBLISH_ASK:=$reason, read from ${piece[1]:-${piece[2]:-}}, one piece of a quoted argument}" ;;
        esac ;;
      # gh stack links or opens PRs as drafts, unless --open marks them ready for review, written plain or quoted.
      stack/link | stack/submit)
        case " $seg " in
          *[[:space:]]--open* | *[[:space:]][\"\'\\]--open*)
            printf -v reason '%s stack %s --open marks PRs ready for review (drafts only; promoting is yours)' "$base" "${lead[2]}"
            [ -n "${piece[1]:-}${piece[2]:-}" ] || { printf '%s' "$reason"; return 0; }
            : "${_GUARDRAILS_PUBLISH_ASK:=$reason, read from ${piece[1]:-${piece[2]:-}}, one piece of a quoted argument}" ;;
        esac ;;
    esac

    # A verb read from one piece of a quoted argument of several words may not be the command's, as the shell passes the
    # argument whole, so it asks; any whole verb after it still blocks.
    for n in 1 2 3; do
      [ "$n" -lt "${#lead[@]}" ] || break
      case "$_GUARDRAILS_PUBLISH_VERBS" in
        *" ${lead[$n]} "*)
          printf -v reason '%s %s publishes under your name' "$base" "${lead[$n]}"
          [ -n "${piece[$n]:-}" ] || { printf '%s' "$reason"; return 0; }
          : "${_GUARDRAILS_PUBLISH_ASK:=$reason, read from ${piece[$n]}, one piece of a quoted argument}" ;;
      esac
    done
  done < <(_guardrails_split_segments "$cmdline")
  # rc 2 asks, with the first such reason, only once no command blocks.
  [ "$depth" -gt 0 ] || [ -z "$_GUARDRAILS_PUBLISH_ASK" ] || { printf '%s' "$_GUARDRAILS_PUBLISH_ASK"; return 2; }
  return 1
}
