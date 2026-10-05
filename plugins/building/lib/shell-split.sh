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
# If the quotes never close, the shell would not run the input at all; it is then split
# line by line, resetting quotes on each, so no command can hide behind a false quote.
#
# Usage: _guardrails_split_segments "<cmdline>" → one segment per line.

# carry=1 carries quotes across lines and exits 3 if they never close; carry=0 resets them per line.
_GUARDRAILS_SPLIT_AWK='
  BEGIN { sq = sprintf("%c", 39); dq = sprintf("%c", 34); bs = sprintf("%c", 92); hd = ""; d = 0; q = ""; out = ""; cont = 0 }
  {
    if (hd != "") {
      t = $0
      sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t)
      if (t == hd) hd = ""
      next
    }
    if (!carry) { q = ""; out = "" }
    else if (q == "" && !cont) out = ""
    cont = 0; ar = 0; n = length($0)
    for (i = 1; i <= n; i++) {
      c = substr($0, i, 1)

      # A backslash makes the next character literal, except inside single quotes.
      # At the end of an unquoted line it joins the next line to this one.
      if (carry && c == bs && q != sq) {
        if (i == n) { if (q == "") cont = 1; else out = out c; break }
        out = out c substr($0, i + 1, 1); i++; continue
      }

      # An enclosing quote does not reach inside $( ), where quoting restarts and
      # a <<WORD is a real opener. Depth outlives the line because the closing )
      # of a `-m "$(cat <<EOF ...)"` body lands on a later one.
      if (q != sq && q != "a" && c == "$" && substr($0, i + 1, 1) == "(" && substr($0, i + 2, 1) != "(") {
        st[++d] = q; q = ""; out = out "$("; i++; continue
      }
      if (q != "") { out = out c; if (c == q || (q == "a" && c == sq)) q = ""; continue }
      if (carry && c == "$" && substr($0, i + 1, 1) == sq) { q = "a"; out = out c sq; i++; continue }
      if (c == sq || c == dq) { q = c; out = out c; continue }

      # A word that starts with # comments out the rest of the line.
      if (carry && c == "#" && (i == 1 || substr($0, i - 1, 1) ~ /[ \t;&|()<>]/)) break

      # (( )) is arithmetic, where << is a bit shift rather than a redirect.
      # Miscounting only suppresses heredoc detection, which is the safe way to err.
      if (c == "(" && substr($0, i + 1, 1) == "(") { ar++; out = out "(("; i++; continue }
      if (c == ")" && substr($0, i + 1, 1) == ")" && ar > 0) { ar--; out = out "))"; i++; continue }
      if (c == ")" && d > 0) { q = st[d--]; out = out c; continue }

      # <<WORD / <<-WORD / <<"WORD" opens a heredoc; <<< is a here-string.
      if (c == "<" && substr($0, i + 1, 1) == "<" && substr($0, i + 2, 1) != "<" && ar == 0) {
        j = i + 2
        if (substr($0, j, 1) == "-") j++
        while (substr($0, j, 1) == " " || substr($0, j, 1) == "\t") j++
        dl = ""; qc = substr($0, j, 1)
        if (qc == sq || qc == dq) {
          j++
          while (j <= n && substr($0, j, 1) != qc) { dl = dl substr($0, j, 1); j++ }
          j++
        } else {
          while (j <= n && substr($0, j, 1) ~ /[A-Za-z0-9_]/) { dl = dl substr($0, j, 1); j++ }
          if (dl ~ /^[0-9]+$/) dl = ""   # a bare number is a shift operand, not a delimiter
        }
        if (dl != "") { hd = dl; out = out "<<"; i = j - 1; continue }
      }

      if ((c == "&" && substr($0, i + 1, 1) == "&") ||
          (c == "|" && substr($0, i + 1, 1) == "|")) { out = out "\n"; i++; continue }
      if (c == "|" || c == ";") { out = out "\n"; continue }
      out = out c
    }
    # Inside a quote the line break is data, so the segment goes on; a joined line goes on too.
    if (carry && q != "") { out = out " "; next }
    if (cont) next
    print out
  }
  END { if (carry && (q != "" || cont)) exit 3 }'

_guardrails_split_segments() {
  local segs
  if segs="$(printf '%s' "$1" | awk -v carry=1 "$_GUARDRAILS_SPLIT_AWK")"; then
    [ -z "$segs" ] || printf '%s\n' "$segs"
  else
    printf '%s' "$1" | awk -v carry=0 "$_GUARDRAILS_SPLIT_AWK"
  fi
}
