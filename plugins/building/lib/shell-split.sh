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
# positive, never a missed command.
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
    function subopen(k, start) {
      if (k > 1) lp[k - 1, ++ln[k - 1]] = substr($0, cs[k - 1], start - cs[k - 1])
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
      if (k > 1) cs[k - 1] = e
    }
    BEGIN { sq = sprintf("%c", 39); dq = sprintf("%c", 34); bs = sprintf("%c", 92); hd = ""; d = 0; q = ""; out = ""; cont = 0; wb = 1; fw = ""; fwd = 0; fwe = 0 }
    {
      # A heredoc body starts once its opening line ends, and a backslash-newline has not ended it.
      if (hd != "" && !cont) {
        t = $0
        sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t)
        if (t == hd) hd = ""
        next
      }
      if (!carry) q = ""
      if (!cont) wb = 1
      # fw is the first word of the segment, once fwd = 2; a heredoc fed to a shell is the script it runs.
      if (carry && q == "" && !cont) { fw = ""; fwd = 0; fwe = 0 }
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
          out = out c chars[i + 1]; i++; wb = 0; continue
        }

        # An enclosing quote does not reach inside $( ), where quoting restarts and
        # a <<WORD is a real opener. Depth outlives the line because the closing )
        # of a `-m "$(cat <<EOF ...)"` body lands on a later one.
        if (q != sq && q != "ansi" && q != "bt" && c == "$" && chars[i + 1] == "(" && chars[i + 2] != "(") {
          st[++d] = q; sw[d] = fw; swd[d] = fwd; swe[d] = fwe; q = ""; fw = ""; fwd = 0; fwe = 0; out = out "$("
          if (carry) { kind[d] = "$"; subopen(d, i + 2) }
          i++; wb = 1; continue
        }
        # A backtick substitution ends at the next unescaped backtick, whatever quotes it holds.
        if (carry && c == "`" && q == "bt") { subclose(d, i); fw = sw[d]; fwd = swd[d]; fwe = swe[d]; q = st[d--]; out = out c; wb = 0; continue }
        if (carry && c == "`" && (q == "" || q == dq)) {
          st[++d] = q; sw[d] = fw; swd[d] = fwd; swe[d] = fwe; kind[d] = "`"; subopen(d, i + 1); q = "bt"; out = out c; continue
        }
        # An ANSI-C string ends only at a single quote, so its marker is longer than any character.
        if (q != "") { out = out c; wb = 0; if (c == q || (q == "ansi" && c == sq)) q = ""; continue }
        if (carry && c == "$" && chars[i + 1] == sq) { q = "ansi"; out = out c sq; i++; continue }
        if (c == sq || c == dq) { q = c; out = out c; continue }
        if (carry && (c == "<" || c == ">") && chars[i + 1] == "(") {
          st[++d] = q; sw[d] = fw; swd[d] = fwd; swe[d] = fwe; fw = ""; fwd = 0; fwe = 0; kind[d] = "$"; subopen(d, i + 2); out = out c "("; i++; wb = 1; continue
        }

        # A word that starts with # comments out the rest of the line. wb marks a word start: after a
        # blank or an operator, but not after an escape, or the ) closing a $( ), <( ) or $(( )).
        if (carry && c == "#" && wb) break

        # (( )) is arithmetic, where << is a bit shift rather than a redirect.
        # Miscounting only suppresses heredoc detection, which is the safe way to err.
        if (c == "(" && chars[i + 1] == "(") { ad[++ar] = (chars[i - 1] == "$"); out = out "(("; i++; wb = 0; continue }
        if (c == ")" && chars[i + 1] == ")" && ar > 0) { wb = !ad[ar--]; out = out "))"; i++; continue }
        if (c == ")" && d > 0) { if (carry) subclose(d, i); fw = sw[d]; fwd = swd[d]; fwe = swe[d]; q = st[d--]; out = out c; wb = 0; continue }

        # <<WORD / <<-WORD / <<"WORD" opens a heredoc; <<< is a here-string.
        if (carry && c == "<" && (chars[i + 1] chars[i + 2]) == "<<") { out = out "<<<"; i += 2; wb = 1; continue }
        if (c == "<" && chars[i + 1] == "<" && chars[i + 2] != "<" && ar == 0) {
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
            sh = fw; while ((k = index(sh, "/")) > 0) sh = substr(sh, k + 1)
            if (!carry || !fwd || !index(" sh bash zsh dash ksh ", " " sh " ")) hd = dl
            out = out "<<"; i = j - 1; wb = 0; continue
          }
        }

        if ((c == "&" && chars[i + 1] == "&") ||
            (c == "|" && chars[i + 1] == "|")) {
          if (carry && d > 0) { subemit(d, i); cs[d] = i + 2 }
          out = out "\n"; i++; wb = 1; fw = ""; fwd = 0; fwe = 0; continue
        }
        if (c == "|" || c == ";") {
          if (carry && d > 0) { subemit(d, i); cs[d] = i + 1 }
          out = out "\n"; wb = 1; fw = ""; fwd = 0; fwe = 0; continue
        }
        if (carry) wb = (index(" \t<>&(", c) > 0 || (c == ")" && d == 0))
        if (carry && fwd < 2) {
          # A NAME=value word before the command is an assignment, not the command. fw keeps only what a
          # shell name needs, five characters after the last slash, so a long word stays linear.
          if (c != " " && c != "\t") {
            if (c == "=" && fwd) fwe = 1
            if (c == "/") { fw = "" } else if (length(fw) < 5) { fw = fw c }
            fwd = 1
          } else if (fwd == 1) { if (fwe) { fw = ""; fwd = 0; fwe = 0 } else fwd = 2 }
        }
        out = out c
      }
      # Inside a substitution a line break ends a command too, unless quoted, escaped or in backticks.
      if (carry && d > 0) {
        if (kind[d] == "$" && q == "" && !cont) subemit(d, i)
        else lp[d, ++ln[d]] = substr($0, cs[d], i - cs[d]) (cont ? "" : ";")
        cs[d] = 1
      }
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
      if (nxp && (q != "" || cont)) printf "\n"
      for (j = 1; j <= nxp; j++) printf "%s", xp[j]
      if (carry && (q != "" || cont)) exit 3
    }'
}

# A hook that times out lets the command through, so the guards do not read a command past these limits:
# its length, the segments in its two splits, and the shells and evals it could make them re-read. Within
# them, the slowest guard measured 4.1 s of its 10 s budget (macOS, load 6), on one eval re-reading 480 curl
# lines of 32 local hosts each (#126).
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
        nw = split(part[i], w, /[^A-Za-z0-9_.-]+/); at = pre
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

# _guardrails_shell_payload <segment> → rc 0 with _GUARDRAILS_PAYLOAD set to the script a shell runs from
# its command line (a -c argument, alone or in a cluster such as -lc, or a here-string) or eval runs,
# else rc 1. It sets a variable rather than printing, since a subshell for every segment is slow.
_guardrails_shell_payload() {
  local seg="$1" i=0 k inner="" here='<<<[[:space:]]*(.*)$'
  local -a toks
  case "$seg" in *eval* | *'<<<'* | *-*c*) ;; *) return 1 ;; esac
  read -r -a toks <<<"$seg" || return 1
  while [ "$i" -lt "${#toks[@]}" ]; do
    case "${toks[$i]}" in [A-Za-z_]*=*) i=$((i + 1)) ;; *) break ;; esac
  done
  case "${toks[$i]:-}" in
    eval) inner="${toks[*]:$((i + 1))}" ;;
    sh | bash | zsh | dash | ksh | */sh | */bash | */zsh | */dash | */ksh)
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
  local i=0 shell
  local -a toks
  case "$1" in *'<'*) return 1 ;; esac
  read -r -a toks <<<"$1" || return 1
  while [ "$i" -lt "${#toks[@]}" ]; do
    case "${toks[$i]}" in [A-Za-z_]*=*) i=$((i + 1)) ;; *) break ;; esac
  done
  case "${toks[$i]:-}" in sh | bash | zsh | dash | ksh | */sh | */bash | */zsh | */dash | */ksh) ;; *) return 1 ;; esac
  shell="${toks[$i]##*/}"
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
