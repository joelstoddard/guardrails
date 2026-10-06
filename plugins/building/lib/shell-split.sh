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
    BEGIN { sq = sprintf("%c", 39); dq = sprintf("%c", 34); bs = sprintf("%c", 92); hd = ""; d = 0; q = ""; out = ""; cont = 0; wb = 1 }
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
        if (q != sq && q != "ansi" && c == "$" && chars[i + 1] == "(" && chars[i + 2] != "(") {
          st[++d] = q; q = ""; out = out "$("; i++; wb = 1; continue
        }
        # An ANSI-C string ends only at a single quote, so its marker is longer than any character.
        if (q != "") { out = out c; wb = 0; if (c == q || (q == "ansi" && c == sq)) q = ""; continue }
        if (carry && c == "$" && chars[i + 1] == sq) { q = "ansi"; out = out c sq; i++; continue }
        if (c == sq || c == dq) { q = c; out = out c; continue }
        if (carry && (c == "<" || c == ">") && chars[i + 1] == "(") { st[++d] = q; out = out c "("; i++; wb = 1; continue }

        # A word that starts with # comments out the rest of the line. wb marks a word start: after a
        # blank or an operator, but not after an escape, or the ) closing a $( ), <( ) or $(( )).
        if (carry && c == "#" && wb) break

        # (( )) is arithmetic, where << is a bit shift rather than a redirect.
        # Miscounting only suppresses heredoc detection, which is the safe way to err.
        if (c == "(" && chars[i + 1] == "(") { ad[++ar] = (chars[i - 1] == "$"); out = out "(("; i++; wb = 0; continue }
        if (c == ")" && chars[i + 1] == ")" && ar > 0) { wb = !ad[ar--]; out = out "))"; i++; continue }
        if (c == ")" && d > 0) { q = st[d--]; out = out c; wb = 0; continue }

        # <<WORD / <<-WORD / <<"WORD" opens a heredoc; <<< is a here-string.
        if (carry && c == "<" && (chars[i + 1] chars[i + 2]) == "<<") { out = out "<<<"; i += 2; wb = 1; continue }
        if (c == "<" && chars[i + 1] == "<" && chars[i + 2] != "<" && ar == 0) {
          j = i + 2
          if (chars[j] == "-") j++
          while (chars[j] == " " || chars[j] == "\t") j++
          dl = ""; qc = chars[j]
          if (carry) {
            # The delimiter is a whole shell word, as the shell reads it: quotes and backslashes removed.
            qd = ""; quoted = 0
            for (; j <= n; j++) {
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
          if (dl != "") { hd = dl; out = out "<<"; i = j - 1; wb = 0; continue }
        }

        if ((c == "&" && chars[i + 1] == "&") ||
            (c == "|" && chars[i + 1] == "|")) { out = out "\n"; i++; wb = 1; continue }
        if (c == "|" || c == ";") { out = out "\n"; wb = 1; continue }
        if (carry) wb = (index(" \t<>&(", c) > 0 || (c == ")" && d == 0))
        out = out c
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
    END { if (carry && (q != "" || cont)) exit 3 }'
}

# A hook that times out lets the command through, so the guards do not try to read one this long.
# At this size the slowest guard takes about 2 s of its 10 s budget; see issue #64.
_GUARDRAILS_SPLIT_MAX=262144

# _guardrails_unreadable <cmdline> → rc 0 and a reason if a guard cannot read the command in full:
# too long to read in time, or a split whose awk aborted, as BSD awk does on invalid bytes (#76).
_guardrails_unreadable() {
  local rc
  if [ "${#1}" -gt "$_GUARDRAILS_SPLIT_MAX" ]; then
    printf '%s characters is too long to read in time' "${#1}"; return 0
  fi
  _guardrails_split_awk 1 "$1" >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] || [ "$rc" = 3 ] || { printf 'splitting it failed (awk exit %s)' "$rc"; return 0; }
  _guardrails_split_awk 0 "$1" >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] || { printf 'splitting it line by line failed (awk exit %s)' "$rc"; return 0; }
  return 1
}

_guardrails_split_segments() {
  local segs closed=1
  if [ "${_GUARDRAILS_SPLIT_PER_LINE:-}" = 1 ]; then _guardrails_split_awk 0 "$1"; return; fi
  segs="$(_guardrails_split_awk 1 "$1")" || closed=0
  [ -z "$segs" ] || printf '%s\n' "$segs"
  [ "$closed" = 1 ] || _guardrails_split_awk 0 "$1"
}
