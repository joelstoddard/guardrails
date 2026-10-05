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

# carry=1 carries quotes across lines and exits 3 if they never close; carry=0 resets them per line.
_guardrails_split_awk() {
  printf '%s' "$2" | awk -v carry="$1" '
    BEGIN { sq = sprintf("%c", 39); dq = sprintf("%c", 34); bs = sprintf("%c", 92); hd = ""; d = 0; q = ""; out = ""; cont = 0; wb = 1 }
    {
      # A heredoc body starts once its opening line ends, and a backslash-newline has not ended it.
      if (hd != "" && !cont) {
        t = $0
        sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t)
        if (t == hd) hd = ""
        next
      }
      if (!carry) { q = ""; out = "" }
      else if (q == "" && !cont) out = ""
      if (!cont) wb = 1
      cont = 0; ar = 0; n = length($0)
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)

        # A backslash makes the next character literal, except inside single quotes.
        # At the end of an unquoted line it joins the next line to this one.
        if (carry && c == bs && q != sq) {
          if (i == n) { if (q == "") cont = 1; else out = out c; break }
          out = out c substr($0, i + 1, 1); i++; wb = 0; continue
        }

        # An enclosing quote does not reach inside $( ), where quoting restarts and
        # a <<WORD is a real opener. Depth outlives the line because the closing )
        # of a `-m "$(cat <<EOF ...)"` body lands on a later one.
        if (q != sq && q != "ansi" && c == "$" && substr($0, i + 1, 1) == "(" && substr($0, i + 2, 1) != "(") {
          st[++d] = q; q = ""; out = out "$("; i++; wb = 1; continue
        }
        # An ANSI-C string ends only at a single quote, so its marker is longer than any character.
        if (q != "") { out = out c; wb = 0; if (c == q || (q == "ansi" && c == sq)) q = ""; continue }
        if (carry && c == "$" && substr($0, i + 1, 1) == sq) { q = "ansi"; out = out c sq; i++; continue }
        if (c == sq || c == dq) { q = c; out = out c; continue }
        if (carry && (c == "<" || c == ">") && substr($0, i + 1, 1) == "(") { st[++d] = q; out = out c "("; i++; wb = 1; continue }

        # A word that starts with # comments out the rest of the line. wb marks a word start: after a
        # blank or an operator, but not after an escape, or the ) closing a $( ), <( ) or $(( )).
        if (carry && c == "#" && wb) break

        # (( )) is arithmetic, where << is a bit shift rather than a redirect.
        # Miscounting only suppresses heredoc detection, which is the safe way to err.
        if (c == "(" && substr($0, i + 1, 1) == "(") { ad[++ar] = (substr($0, i - 1, 1) == "$"); out = out "(("; i++; wb = 0; continue }
        if (c == ")" && substr($0, i + 1, 1) == ")" && ar > 0) { wb = !ad[ar--]; out = out "))"; i++; continue }
        if (c == ")" && d > 0) { q = st[d--]; out = out c; wb = 0; continue }

        # <<WORD / <<-WORD / <<"WORD" opens a heredoc; <<< is a here-string.
        if (carry && c == "<" && substr($0, i + 1, 2) == "<<") { out = out "<<<"; i += 2; wb = 1; continue }
        if (c == "<" && substr($0, i + 1, 1) == "<" && substr($0, i + 2, 1) != "<" && ar == 0) {
          j = i + 2
          if (substr($0, j, 1) == "-") j++
          while (substr($0, j, 1) == " " || substr($0, j, 1) == "\t") j++
          dl = ""; qc = substr($0, j, 1)
          if (carry) {
            # The delimiter is a whole shell word, as the shell reads it: quotes and backslashes removed.
            qd = ""; quoted = 0
            for (; j <= n; j++) {
              ch = substr($0, j, 1)
              if (qd != "") { if (ch == qd) qd = ""; else dl = dl ch; continue }
              if (ch == sq || ch == dq) { qd = ch; quoted = 1; continue }
              if (ch == bs) { dl = dl substr($0, ++j, 1); quoted = 1; continue }
              if (index(" \t;&|<>()", ch)) break
              dl = dl ch
            }
            if (!quoted && index("0123456789", substr(dl, 1, 1))) dl = ""   # 1<<2 inside $[ ] or a split (( )) is a shift
          } else if (qc == sq || qc == dq) {
            j++
            while (j <= n && substr($0, j, 1) != qc) { dl = dl substr($0, j, 1); j++ }
            j++
          } else {
            while (j <= n && substr($0, j, 1) ~ /[A-Za-z0-9_]/) { dl = dl substr($0, j, 1); j++ }
            if (dl ~ /^[0-9]+$/) dl = ""   # a bare number is a shift operand, not a delimiter
          }
          if (dl != "") { hd = dl; out = out "<<"; i = j - 1; wb = 0; continue }
        }

        if ((c == "&" && substr($0, i + 1, 1) == "&") ||
            (c == "|" && substr($0, i + 1, 1) == "|")) { out = out "\n"; i++; wb = 1; continue }
        if (c == "|" || c == ";") { out = out "\n"; wb = 1; continue }
        wb = (index(" \t<>&(", c) > 0 || (c == ")" && d == 0))
        out = out c
      }
      # A line break inside a quote is data here, but a separator to the sh -c or eval that re-splits
      # the quote, so it is written as a semicolon. Flushing each line keeps a long quote linear.
      if (carry && q != "") { printf "%s;", out; out = ""; next }
      if (cont) { printf "%s", out; out = ""; next }
      print out
    }
    END { if (carry && (q != "" || cont)) exit 3 }'
}

_guardrails_split_segments() {
  local segs closed=1
  segs="$(_guardrails_split_awk 1 "$1")" || closed=0
  [ -z "$segs" ] || printf '%s\n' "$segs"
  [ "$closed" = 1 ] || _guardrails_split_awk 0 "$1"
}
