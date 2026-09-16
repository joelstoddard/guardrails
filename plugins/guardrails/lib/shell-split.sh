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
# Usage: _guardrails_split_segments "<cmdline>" → one segment per line.

_guardrails_split_segments() {
  printf '%s' "$1" | awk '
    BEGIN { sq = sprintf("%c", 39); dq = sprintf("%c", 34); hd = "" }
    {
      if (hd != "") {
        t = $0
        sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t)
        if (t == hd) hd = ""
        next
      }
      q = ""; out = ""; ar = 0; n = length($0)
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)
        if (q != "") { out = out c; if (c == q) q = ""; continue }
        if (c == sq || c == dq) { q = c; out = out c; continue }

        # (( )) is arithmetic, where << is a bit shift rather than a redirect.
        # Miscounting only suppresses heredoc detection, which is the safe way to err.
        if (c == "(" && substr($0, i + 1, 1) == "(") { ar++; out = out "(("; i++; continue }
        if (c == ")" && substr($0, i + 1, 1) == ")" && ar > 0) { ar--; out = out "))"; i++; continue }

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
      print out
    }'
}
