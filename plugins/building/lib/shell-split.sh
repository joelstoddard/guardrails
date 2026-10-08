#!/usr/bin/env bash
# shell-split.sh — split a command line into segments on shell operators, ignoring
# operators that appear inside quotes.
#
# Splitting blindly does not merely over-split a real command, it fabricates one that
# was never run: the pipes in `grep -E 'a|cd /evil' f` yield a segment whose first word
# is `cd`, which is enough to send a guard looking at the wrong directory. Shared by
# git-cmd.sh and publish-cmd.sh so the two hooks cannot drift apart on it.
#
# Heredoc bodies are dropped for the same reason: a `<<EOF` body is data the command
# writes, not commands the shell runs, and prose routinely starts a line with a word
# a guard would read as a tool and a verb. Detection errs toward keeping lines —
# anything not recognised as an opener is still scanned, so a miss costs a false
# positive, never a missed command. The shell does run the $( ) and backticks in the
# body of an unquoted <<EOF, so the split that carries quotes writes those as segments.
#
# A quoted argument can span lines, so quote state carries across them, with the
# shell's escapes, comments and $'...' strings, and a backslash-newline joins two lines.
# If the quotes never close, bash still runs the lines before them, so every line is then
# also split on its own, with quotes reset, and no command can hide behind a false quote.
#
# Usage: _guardrails_split_segments "<cmdline>" → one segment per line.
#        _GUARDRAILS_SPLIT_PER_LINE=1 resets quotes on every line, the split from before they carried,
#        which the guards keep as a cross-check so that carrying never weakens them.

# carry=1 carries quotes across lines and exits 3 if they never close; carry=0 resets them per line.
_guardrails_split_awk() {
  printf '%s' "$2" | awk -v carry="$1" '
    # Carry mode also writes each command inside a $( ), <( ) or >( ) as a segment of its own, after the
    # rest, as backticks are written as sh -c "...". Level k of nesting holds its text from cs[k] on this
    # line, after pieces lp[k, 1..ln[k]] from earlier lines; a nested level leaves its opener and closer.
    # Levels at or below hb enclose an unquoted heredoc body being read, whose text is data, not theirs.
    function subopen(k, start) {
      if (k > hb + 1) lp[k - 1, ++ln[k - 1]] = substr($0, cs[k - 1], start - cs[k - 1])
      cs[k] = start; ln[k] = 0
    }
    function subemit(k, e,   j, t) {
      t = substr($0, cs[k], e - cs[k])
      if (t == "" && !ln[k]) return
      if (kind[k] == "`") xp[++nxp] = "sh -c \""
      for (j = 1; j <= ln[k]; j++) xp[++nxp] = lp[k, j]
      xp[++nxp] = t
      if (kind[k] == "`") xp[++nxp] = "\""
      xp[++nxp] = "\n"; ln[k] = 0
    }
    function subclose(k, e) {
      subemit(k, e)
      if (k > hb + 1) cs[k - 1] = e
    }
    # A shell word anywhere before a heredoc opener makes the body its script, so no wrapper hides one (#90).
    function wordend() { if (index(" sh bash zsh dash ksh ", " " cw " ")) fsh = 1; cw = ""; qd = 0 }
    # The shell ends a body at its delimiter line, even inside a substitution, which is then never closed.
    function bodyend() {
      for (; d > hb; d--) subemit(d, cs[d])
      q = hq; inb = 0; hb = 0; cont = 0
    }
    BEGIN { sq = sprintf("%c", 39); dq = sprintf("%c", 34); bs = sprintf("%c", 92); hd = ""; d = 0; q = ""; out = ""; cont = 0; wb = 1; cw = ""; fsh = 0 }
    {
      # A heredoc body starts once its opening line ends, and a backslash-newline has not ended it.
      if (hd != "" && (!cont || inb)) {
        t = $0
        sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t)
        if (t == hd) { hd = ""; hx = 0; if (inb) bodyend(); next }
        # The shell runs the $( ) and backticks of an unquoted body, where quotes are text, as in q = "hd".
        if (!hx) next
        if (!inb) { inb = 1; hb = d; hq = q; q = "hd" }
      }
      if (!carry) q = ""
      if (!cont) wb = 1
      # cw is the end of the word being read, and fsh notes a shell word before it in the segment.
      if (carry && q == "" && !cont) { cw = ""; fsh = 0; qd = 0 }
      # Indexing the line split into characters keeps the scan linear: substr rescans the line on each call.
      cont = 0; ar = 0; n = split($0, chars, "")
      for (i = 1; i <= n; i++) {
        # Appending to one ever longer string is quadratic, so every 256 characters it moves into piece.
        if (++appended > 256) { piece[++np] = out; out = ""; appended = 0 }
        c = chars[i]

        # A backslash makes the next character literal, except inside single quotes.
        # At the end of an unquoted line it joins the next line to this one.
        if (carry && c == bs && q != sq) {
          if (i == n) { if (q == "") cont = 1; else out = out c; break }
          # The shell drops the backslash, so the character is part of the word, as in ba\sh (#111).
          if (!qd) { if (chars[i + 1] == "/") cw = ""; else if (length(cw) < 5) cw = cw chars[i + 1] }
          out = out c chars[i + 1]; i++; wb = 0; continue
        }

        # An enclosing quote does not reach inside $( ), where quoting restarts and
        # a <<WORD is a real opener. Depth outlives the line because the closing )
        # of a `-m "$(cat <<EOF ...)"` body lands on a later one.
        if (q != sq && q != "ansi" && q != "bt" && c == "$" && chars[i + 1] == "(" && chars[i + 2] != "(") {
          st[++d] = q; sw[d] = cw; sf[d] = fsh; q = ""; cw = ""; fsh = 0; qd = 0; out = out "$("
          if (carry) { kind[d] = "$"; subopen(d, i + 2) }
          i++; wb = 1; continue
        }
        # A backtick substitution ends at the next unescaped backtick, whatever quotes it holds.
        if (carry && c == "`" && q == "bt") { subclose(d, i); cw = sw[d]; fsh = sf[d]; qd = 1; q = st[d--]; out = out c; wb = 0; continue }
        if (carry && c == "`" && (q == "" || q == dq || q == "hd")) {
          st[++d] = q; sw[d] = cw; sf[d] = fsh; kind[d] = "`"; subopen(d, i + 1); q = "bt"; out = out c; continue
        }
        # An ANSI-C string ends only at a single quote, so its marker is longer than any character.
        if (q != "") {
          out = out c; wb = 0
          if (c == q || (q == "ansi" && c == sq)) q = ""
          else if (carry && !qd && q != "bt" && q != "hd") {
            # A quoted first word is a shell when the quote ends with it or an option follows it, as when ssh
            # is given bash -s in quotes (#111); a later word in the quote is prose, as in --title "bash fix".
            if (c == " " || c == "\t") { if (chars[i + 1] == "-") wordend(); cw = ""; qd = 1 }
            else if (c == "/") cw = ""; else if (length(cw) < 5) cw = cw c
          }
          continue
        }
        if (carry && c == "$" && chars[i + 1] == sq) { q = "ansi"; out = out c sq; i++; continue }
        if (c == sq || c == dq) { q = c; out = out c; continue }
        if (carry && (c == "<" || c == ">") && chars[i + 1] == "(") {
          st[++d] = q; sw[d] = cw; sf[d] = fsh; cw = ""; fsh = 0; qd = 0; kind[d] = "$"; subopen(d, i + 2); out = out c "("; i++; wb = 1; continue
        }

        # A word that starts with # comments out the rest of the line. wb marks a word start: after a
        # blank or an operator, but not after an escape, or the ) closing a $( ), <( ) or $(( )).
        if (carry && c == "#" && wb) break

        # (( )) is arithmetic, where << is a bit shift rather than a redirect.
        # Miscounting only suppresses heredoc detection, which is the safe way to err.
        if (c == "(" && chars[i + 1] == "(") { ad[++ar] = (chars[i - 1] == "$"); out = out "(("; i++; wb = 0; continue }
        if (c == ")" && chars[i + 1] == ")" && ar > 0) { wb = !ad[ar--]; out = out "))"; i++; continue }
        if (c == ")" && d > 0) { if (carry) subclose(d, i); cw = sw[d]; fsh = sf[d]; qd = 1; q = st[d--]; out = out c; wb = 0; continue }

        # <<WORD / <<-WORD / <<"WORD" opens a heredoc; <<< is a here-string.
        if (carry && c == "<" && (chars[i + 1] chars[i + 2]) == "<<") { out = out "<<<"; i += 2; wb = 1; continue }
        # A body is read to its delimiter alone, so a heredoc opened in its substitution opens no other.
        if (c == "<" && chars[i + 1] == "<" && chars[i + 2] != "<" && ar == 0 && !inb) {
          j = i + 2
          if (chars[j] == "-") j++
          while (chars[j] == " " || chars[j] == "\t") j++
          dl = ""; qc = chars[j]
          if (carry) {
            # The delimiter is a whole shell word, as the shell reads it: quotes and backslashes removed.
            # A delimiter is a short word: past 1024 characters this opens no heredoc, which errs toward
            # scanning and keeps a long word from making the read quadratic.
            qd = ""; quoted = 0; dn = 0
            for (; j <= n; j++) {
              if (++dn > 1024) { dl = ""; break }
              ch = chars[j]
              if (qd != "") { if (ch == qd) qd = ""; else dl = dl ch; continue }
              if (ch == sq || ch == dq) { qd = ch; quoted = 1; continue }
              if (ch == bs) { dl = dl chars[++j]; quoted = 1; continue }
              if (index(" \t;&|<>()", ch)) break
              dl = dl ch
            }
            if (!quoted && index("0123456789", substr(dl, 1, 1))) dl = ""   # 1<<2 inside $[ ] or a split (( )) is a shift
          } else if (qc == sq || qc == dq) {
            s0 = ++j
            while (j <= n && chars[j] != qc) j++
            dl = substr($0, s0, j - s0); j++
          } else {
            s0 = j
            while (j <= n && chars[j] ~ /[A-Za-z0-9_]/) j++
            dl = substr($0, s0, j - s0)
            if (dl ~ /^[0-9]+$/) dl = ""   # a bare number is a shift operand, not a delimiter
          }
          if (dl != "") {
            wordend()
            if (!carry || !fsh) { hd = dl; if (carry && !quoted) hx = 1 }
            out = out "<<"; i = j - 1; wb = 0; continue
          }
        }

        if ((c == "&" && chars[i + 1] == "&") ||
            (c == "|" && chars[i + 1] == "|")) {
          if (carry && d > 0) { subemit(d, i); cs[d] = i + 2 }
          out = out "\n"; i++; wb = 1; cw = ""; fsh = 0; qd = 0; continue
        }
        # A lone & ends a command as ; does, but the & in >&, <&, &> and |& belongs to a redirect or pipe.
        if (carry && ((index("<>", c) && chars[i + 1] == "&") || (c == "&" && chars[i + 1] == ">"))) {
          wordend(); out = out c chars[i + 1]; i++; wb = 1; continue
        }
        if (c == "|" || c == ";" || (carry && c == "&")) {
          j = (carry && c == "|" && chars[i + 1] == "&")
          if (carry && d > 0) { subemit(d, i); cs[d] = i + 1 + j }
          i += j
          out = out "\n"; wb = 1; cw = ""; fsh = 0; qd = 0; continue
        }
        if (carry) wb = (index(" \t<>&(", c) > 0 || (c == ")" && d == 0))
        # cw keeps only what a shell name needs, five characters after the last slash, so a long word stays linear.
        if (carry) { if (index(" \t<>&()", c)) wordend(); else if (c == "/") cw = ""; else if (length(cw) < 5) cw = cw c }
        out = out c
      }
      # Inside a substitution a line break ends a command too, unless quoted, escaped or in backticks.
      if (carry && d > hb) {
        if (kind[d] == "$" && q == "" && !cont) subemit(d, i)
        else lp[d, ++ln[d]] = substr($0, cs[d], i - cs[d]) (cont ? "" : ";")
        cs[d] = 1
      }
      if (inb) { out = ""; np = 0; appended = 0; next }
      # A line is written only once read whole, so an awk that aborts mid-line writes none of it, as
      # before. A line break inside a quote is data here, but a separator to the sh -c or eval that
      # re-splits the quote, so it is written as a semicolon.
      for (k = 1; k <= np; k++) printf "%s", piece[k]
      printf "%s", out; out = ""; np = 0; appended = 0
      if (carry && q != "") { printf ";"; next }
      if (cont) next
      print ""
    }
    END {
      if (inb) bodyend()
      if (nxp && (q != "" || cont)) printf "\n"
      for (j = 1; j <= nxp; j++) printf "%s", xp[j]
      if (carry && (q != "" || cont)) exit 3
    }'
}

# A hook that times out lets the command through, so the guards do not read a command past these limits:
# its length, the segments in its two splits, and the shells and evals it could make them re-read. Within
# them, the slowest guard measured 4.0 s of its 10 s budget (macOS, load 6), on 32,000 env wrappers before a
# commit and on one eval re-reading 480 curl lines of 32 local hosts each (#110).
_GUARDRAILS_SPLIT_MAX=131072
_GUARDRAILS_SPLIT_MAX_SEGMENTS=10000
_GUARDRAILS_SPLIT_MAX_SHELLS=16

# _guardrails_unreadable <cmdline> → rc 0 and a reason if a guard cannot read the command in full:
# too much to read in time, or a split whose awk aborted, as BSD awk does on invalid bytes (#76).
_guardrails_unreadable() {
  local rc carried per_line n s r
  if [ "${#1}" -gt "$_GUARDRAILS_SPLIT_MAX" ]; then
    printf '%s characters is too long to read in time' "${#1}"; return 0
  fi
  carried="$(_guardrails_split_awk 1 "$1" 2>/dev/null)"; rc=$?
  [ "$rc" = 0 ] || [ "$rc" = 3 ] || { printf 'splitting it failed (awk exit %s)' "$rc"; return 0; }
  per_line="$(_guardrails_split_awk 0 "$1" 2>/dev/null)"; rc=$?
  [ "$rc" = 0 ] || { printf 'splitting it line by line failed (awk exit %s)' "$rc"; return 0; }
  # n counts the segments of both splits, s the shells and evals in the carried split, which drops heredoc bodies as
  # data, and r the characters the larger split reads again. See docs/design/git-command-parsing.md
  read -r n s r < <(LC_ALL=C awk '
    FNR == 1 { f++ }
    {
      # A shell reads what follows its -c or <<< as a script, and eval what follows it, so each place after one where
      # a split could cut is a segment, and each character after one is read again (#107).
      L = length($0); np = split($0, part, /[;|&`]|[$<>][(]/)
      for (last = np; last > 0 && part[last] !~ /(^|[ \t])-([^ \t-][^ \t]*)?c|<<</; last--) ;
      n++; k = 0; pre = 0
      for (i = 1; i <= np; i++) {
        t = part[i]; gsub(/["\047\\]/, "", t); nw = split(t, w, /[^A-Za-z0-9_.-]+/); at = pre
        for (j = 1; j <= nw; j++) {
          at += length(w[j]); sh = (w[j] == "sh" || w[j] == "bash" || w[j] == "zsh" || w[j] == "dash" || w[j] == "ksh")
          if (f == 1 && (sh || w[j] == "eval")) s++
          if (w[j] == "eval" || (sh && i <= last)) { k++; r[f] += L - at }
        }
        n += k; pre += length(part[i]) + 1
      }
    }
    END { print n + 0, s + 0, (r[1] > r[2] ? r[1] : r[2]) + 0 }' <(printf '%s\n' "$carried") <(printf '%s\n' "$per_line"))
  # A count the awk could not make compares as unreadable, as test fails on an empty number.
  [ "$n" -le "$_GUARDRAILS_SPLIT_MAX_SEGMENTS" ] 2>/dev/null || { printf '%s segments are too many to read in time' "$n"; return 0; }
  [ "$s" -le "$_GUARDRAILS_SPLIT_MAX_SHELLS" ] 2>/dev/null || { printf '%s shells and evals are too many to re-read in time' "$s"; return 0; }
  [ "$r" -le "$_GUARDRAILS_SPLIT_MAX" ] 2>/dev/null || { printf '%s characters its shells and evals would read again are too many to read in time' "$r"; return 0; }
  return 1
}

_guardrails_split_segments() {
  local segs closed=1
  if [ "${_GUARDRAILS_SPLIT_PER_LINE:-}" = 1 ]; then _guardrails_split_awk 0 "$1"; return; fi
  segs="$(_guardrails_split_awk 1 "$1")" || closed=0
  [ -z "$segs" ] || printf '%s\n' "$segs"
  [ "$closed" = 1 ] || _guardrails_split_awk 0 "$1"
}

# _guardrails_command_at → reads the caller's toks, one segment's words, and sets _GUARDRAILS_CMD_AT to the index of
# the command they run and _GUARDRAILS_CMD to its name, past assignments, keywords, a ( and wrappers with their options.
# _GUARDRAILS_CMD_WRAPPED is 1 when a keyword, ( or wrapper came first. See docs/design/git-command-parsing.md
_guardrails_command_at() {
  _GUARDRAILS_CMD_AT=0; _GUARDRAILS_CMD="${toks[0]:-}"; _GUARDRAILS_CMD_WRAPPED=0
  # Every segment pays for this call, and bash calls a small function faster, so only a word that can come before
  # the command goes on to the loop, which must skip each word named here.
  case "$_GUARDRAILS_CMD" in
    *[=/\(\)\<\>\"\'\\]* | '' | '!' | '{' | if | then | elif | else | while | until | do | in) _guardrails_command_skip ;;
    function | coproc | case) _guardrails_command_skip ;;
    sudo | env | exec | time | xargs | ssh | nohup | command) _guardrails_command_skip ;;
    timeout | nice | stdbuf | doas | setsid | chroot | docker | kubectl) _guardrails_command_skip ;;
    *) [ "${toks[1]:-}" != '()' ] || _guardrails_command_skip ;;   # f () { ...; }
  esac
}

_guardrails_command_skip() {
  local i=0 w b="" vals longs o start ops sub remote=-1 rb
  local redirect='^([0-9]+|\{[A-Za-z_][A-Za-z0-9_]*\})?(&>>|&>|>>|>&|>\||<<<|<<-|<<|<>|<&|>|<)(.*)$'
  while [ "$i" -lt "${#toks[@]}" ]; do
    w="${toks[$i]}"; b=""
    # Most words hold none of < > ( ), so they skip these checks, which every word before the command pays for.
    # A ( opens a subshell, fused to the word after it or not; (( is arithmetic.
    case "$w" in
      *[\<\>\(\)]*) case "$w" in '(('*) ;; '('*) w="${w#(}"; _GUARDRAILS_CMD_WRAPPED=1 ;; esac
        # A redirect can come before the command (#109); an operator alone takes the next word as its target.
        # Patterns sort the usual forms, as a regex per word costs more; a longer fd goes to the regex.
        case "$w" in
          \< | \> | \>\> | \>\| | \<\> | \>\& | \<\& | \&\> | \&\>\> | \<\< | \<\<- | \<\<\< | [0-9]\< | [0-9]\> | \
            [0-9]\>\> | [0-9]\>\| | [0-9]\<\> | [0-9]\>\& | [0-9]\<\& | [0-9]\<\< | [0-9]\<\<- | [0-9]\<\<\<)
            i=$((i + 2)); _GUARDRAILS_CMD_WRAPPED=1; continue ;;
          \<* | \>* | \&\>* | [0-9]\<* | [0-9]\>*) i=$((i + 1)); _GUARDRAILS_CMD_WRAPPED=1; continue ;;
          [0-9]*[\<\>]* | \{*[\<\>]*)
            if [[ $w =~ $redirect ]]; then
              [ -n "${BASH_REMATCH[3]}" ] || i=$((i + 1))
              i=$((i + 1)); _GUARDRAILS_CMD_WRAPPED=1; continue
            fi ;;
        esac
        # A function's header and a case arm's pattern come before the command they run (#110).
        case "$w" in
          *'()'*) [[ $w =~ \(\)(.*)$ ]]; w="${BASH_REMATCH[1]}"; w="${w#[{(]}"; _GUARDRAILS_CMD_WRAPPED=1 ;;
          *')') _GUARDRAILS_CMD_WRAPPED=1; i=$((i + 1)); continue ;;
        esac ;;
    esac
    case "$w" in
      [A-Za-z_]*=*) i=$((i + 1)); continue ;;
      # The shell drops a command word's quotes and backslashes (#111). A name is short, and a long word would
      # make the substitution slow, so only a short word is read this way.
      *[\"\'\\]*) [ "${#w}" -gt 64 ] || { w="${w#\$}"; w="${w//[\"\'\\]/}"; _GUARDRAILS_CMD_WRAPPED=1; } ;;
    esac
    case "$w" in
      '' | '!' | '{' | if | then | elif | else | while | until | do | in) _GUARDRAILS_CMD_WRAPPED=1; i=$((i + 1)); continue ;;
      function) _GUARDRAILS_CMD_WRAPPED=1; i=$((i + 2)); continue ;;
      # A coproc's name comes only before a compound command, and a case's word before its in.
      coproc) _GUARDRAILS_CMD_WRAPPED=1; i=$((i + 1)); case "${toks[$((i + 1))]:-}" in '{' | '('*) i=$((i + 1)) ;; esac; continue ;;
      case) _GUARDRAILS_CMD_WRAPPED=1; for ((i = i + 1; i < ${#toks[@]}; i++)); do [ "${toks[$i]}" = in ] && break; done; continue ;;
    esac
    # ${w##*/} is quadratic on a long word, enough to time the hook out; this regex is linear.
    b="$w"; [[ $b == */* && $b =~ /([^/]*)$ ]] && b="${BASH_REMATCH[1]}"
    # A wrapper runs the command after its options and its operand, if it has one: a duration, root, host or
    # container. vals are its short options that take a value, and longs its long ones (#116).
    ops=0; sub=0; longs=""
    case "$b" in
      sudo) vals=CDghpRrTtUu; longs='--user --group --chdir --close-from --host --prompt --role --type --command-timeout --other-user --chroot' ;;
      env) vals=CPSu; longs='--unset --chdir --split-string' ;;
      exec) vals=a ;;
      time) vals=fo; longs='--output --format' ;;
      xargs) vals=adEIJLnPRSs; longs='--arg-file --delimiter --max-args --max-procs --max-chars --process-slot-var' ;;
      timeout) vals=ks; ops=1; longs='--signal --kill-after' ;;
      nice) vals=n; longs='--adjustment' ;;
      stdbuf) vals=ioe; longs='--input --output --error' ;;
      doas) vals=Cu ;;
      chroot) vals=ugG; ops=1; longs='--userspec --groups' ;;
      nohup | command | setsid) vals="" ;;
      # These run their command elsewhere, as you, so only a shell there is read, like a shell here.
      ssh) vals=BbcDEeFIiJLlmOoPpQRSWw; ops=1; remote="$i"; rb="$b" ;;
      docker)
        [ "${toks[$((i + 1))]:-}" = exec ] || break
        vals=euw; ops=1; sub=1; remote="$i"; rb="$b"; longs='--env --env-file --user --workdir --detach-keys' ;;
      kubectl)
        [ "${toks[$((i + 1))]:-}" = exec ] || break
        vals=cfn; ops=1; sub=1; remote="$i"; rb="$b"; longs='--container --filename --namespace --pod-running-timeout' ;;
      # f () { ...; } names a function before its body.
      *) [ "${toks[$((i + 1))]:-}" != '()' ] || { _GUARDRAILS_CMD_WRAPPED=1; i=$((i + 2)); continue; }; break ;;
    esac
    start="$i"; _GUARDRAILS_CMD_WRAPPED=1; i=$((i + 1 + sub))
    while :; do
      for (( ; i < ${#toks[@]}; i++)); do
        o="${toks[$i]}"
        case "$o" in
          --) i=$((i + 1)); break ;;
          # A long option written with = holds its value.
          --*) case " $longs " in *" $o "*) i=$((i + 1)) ;; esac ;;
          -?*)
            # command -v and -V name a command without running it.
            [[ $b == command && $o == -*[vV]* ]] && { i="$start"; break 3; }
            # In a cluster, the first option taking a value takes the rest of the word, or the next word if none is left.
            [[ -n $vals && -z ${o#-*[$vals]} ]] && i=$((i + 1)) ;;
          *) break ;;
        esac
      done
      [ "$ops" -gt 0 ] || break
      # kubectl takes options after its pod as well.
      ops=0; i=$((i + 1)); [ "$b" = kubectl ] || break
    done
  done
  [ "$i" -lt "${#toks[@]}" ] || b=""
  if [ "$remote" -ge 0 ]; then case "$b" in sh | bash | zsh | dash | ksh) ;; *) i="$remote"; b="$rb" ;; esac; fi
  _GUARDRAILS_CMD_AT="$i"; _GUARDRAILS_CMD="$b"
}

# _guardrails_shell_payload <segment> → rc 0 with _GUARDRAILS_PAYLOAD set to the script a shell runs from
# its command line (a -c argument, alone or in a cluster such as -lc, or a here-string) or eval runs,
# else rc 1. It sets a variable rather than printing, since a subshell for every segment is slow.
_guardrails_shell_payload() {
  local seg="$1" i k inner="" here='<<<[[:space:]]*(.*)$'
  local -a toks
  case "$seg" in *eval* | *'<<<'* | *-*c* | *[\"\'\\]*) ;; *) return 1 ;; esac
  read -r -a toks <<<"$seg" || return 1
  _guardrails_command_at; i="$_GUARDRAILS_CMD_AT"
  case "$_GUARDRAILS_CMD" in
    eval) inner="${toks[*]:$((i + 1))}" ;;
    sh | bash | zsh | dash | ksh)
      for ((k = i + 1; k < ${#toks[@]}; k++)); do
        case "${toks[$k]}" in
          --*) ;;
          -*c*) inner="${toks[*]:$((k + 1))}"; break ;;
        esac
      done
      # Words and a regex, as searching with ${seg#*<<<} is quadratic on a long segment.
      [ -n "$inner" ] || { [[ $seg =~ $here ]] && inner="${BASH_REMATCH[1]}"; } ;;
    *) return 1 ;;
  esac
  # Slices, as ${inner#["']} and ${inner%["']} are quadratic on a long payload in a UTF-8 locale (#107).
  case "${inner:0:1}" in [\"\']) inner="${inner:1}" ;; esac
  case "${inner: -1}" in [\"\']) inner="${inner:0:${#inner}-1}" ;; esac
  [ -n "$inner" ] && [ "$inner" != "$seg" ] || return 1
  _GUARDRAILS_PAYLOAD="$inner"
}

# _guardrails_shell_reads_stdin <segment> → rc 0 and a reason if the segment is a shell reading commands
# from a stdin the command line does not show, such as a pipe; not a heredoc, here-string, file or script.
_guardrails_shell_reads_stdin() {
  local i shell
  local -a toks
  case "$1" in *'<'*) return 1 ;; esac
  read -r -a toks <<<"$1" || return 1
  _guardrails_command_at; i="$_GUARDRAILS_CMD_AT"; shell="$_GUARDRAILS_CMD"
  case "$shell" in sh | bash | zsh | dash | ksh) ;; *) return 1 ;; esac
  for ((i = i + 1; i < ${#toks[@]}; i++)); do
    case "${toks[$i]}" in
      -o | +o | -O | +O | --rcfile | --init-file) i=$((i + 1)) ;;
      --*) ;;
      - | -*s*) break ;;
      -* | +*) ;;
      *) return 1 ;;
    esac
  done
  printf '%s reads commands from stdin, which the command line does not show' "$shell"
}

# _guardrails_names_shell <text> → rc 0 if a shell or eval appears in it as a word, as it must to run.
_guardrails_names_shell() {
  local w
  case "$1" in *sh* | *eval*) ;; *) return 1 ;; esac
  for w in sh bash zsh dash ksh eval; do
    case " $1 " in *[!A-Za-z0-9_.-]"$w"[!A-Za-z0-9_.-]*) return 0 ;; esac
  done
  return 1
}

# _guardrails_unseen_shell_stdin <cmdline> → rc 0 and a reason if a shell in it, or in a script it runs,
# reads commands from stdin that the command line does not show.
_guardrails_unseen_shell_stdin() {
  local depth="${2:-0}" seg
  [ "$depth" -gt 4 ] && return 1
  # This pass runs on every command, so only text naming a shell or eval as a word is looked at closely.
  _guardrails_names_shell "$1" || return 1
  while IFS= read -r seg; do
    _guardrails_names_shell "$seg" || continue
    if _guardrails_shell_payload "$seg"; then
      _guardrails_unseen_shell_stdin "$_GUARDRAILS_PAYLOAD" "$((depth + 1))" && return 0
    else
      _guardrails_shell_reads_stdin "$seg" && return 0
    fi
  done < <(_guardrails_split_segments "$1")
  return 1
}
