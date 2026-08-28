#!/usr/bin/env bash
# shell-split.sh — split a command line into segments on shell operators, ignoring
# operators that appear inside quotes.
#
# Splitting blindly does not merely over-split a real command, it fabricates one that
# was never run: the pipes in `grep -E 'a|cd /evil' f` yield a segment whose first word
# is `cd`, which is enough to send a guard looking at the wrong directory. Shared by
# git-cmd.sh and publish-cmd.sh so the two hooks cannot drift apart on it.
#
# Usage: _guardrails_split_segments "<cmdline>" → one segment per line.

_guardrails_split_segments() {
  printf '%s' "$1" | awk '
    BEGIN { sq = sprintf("%c", 39); dq = sprintf("%c", 34) }
    {
      q = ""; out = ""; n = length($0)
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)
        if (q != "") { out = out c; if (c == q) q = ""; continue }
        if (c == sq || c == dq) { q = c; out = out c; continue }
        if ((c == "&" && substr($0, i + 1, 1) == "&") ||
            (c == "|" && substr($0, i + 1, 1) == "|")) { out = out "\n"; i++; continue }
        if (c == "|" || c == ";") { out = out "\n"; continue }
        out = out c
      }
      print out
    }'
}
