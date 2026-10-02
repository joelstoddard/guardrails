#!/usr/bin/env bash
# findings.sh — read the "Findings outside scope" list out of a report or final message.
#
# Usage: _guardrails_findings "<text>"  → one finding per line, continuation lines joined
#        _guardrails_untracked "<text>" → the findings whose line does not end with a reference

# A reference counts only at the end of the item, so a mid-sentence "PR #85" is not one.
_GUARDRAILS_TRACKED_RE='(github\.com/[^[:space:]]+/issues/[0-9]+|linear\.app/[^[:space:]]+/issue/[A-Za-z0-9-]+[^[:space:]]*|(^|[^A-Za-z0-9&])#[0-9]+|[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+|\((declined|asked)\))[]).>]*[[:space:]]*$'

_guardrails_findings() {
  printf '%s\n' "$1" | awk '
    function flush() { if (item != "") print item; item = "" }
    /^[[:space:]]*(```|~~~)/ { infence = !infence; next }
    infence { next }
    /^[[:space:]]*#+[[:space:]]/ || /^[[:space:]]*\*\*[^*]+\*\*[[:space:]]*$/ {
      flush(); insec = (tolower($0) ~ /findings outside scope/); next
    }
    !insec { next }
    /^([-*+]|[0-9]+[.)])[[:space:]]+/ {
      flush(); line = $0; sub(/^([-*+]|[0-9]+[.)])[[:space:]]+/, "", line)
      if (tolower(line) !~ /^(none|n\/a|nothing)[.!]?[[:space:]]*$/) item = line
      next
    }
    /^[[:space:]]+[^[:space:]]/ { if (item != "") { l = $0; sub(/^[[:space:]]+/, "", l); item = item " " l }; next }
    /^[[:space:]]*$/ { next }
    { flush() }
    END { flush() }'
}

_guardrails_untracked() {
  _guardrails_findings "$1" | grep -vE -- "$_GUARDRAILS_TRACKED_RE"
}

# _guardrails_findings_file <session_id> → where SubagentStop keeps findings for the Stop gate.
# Fails on an id that is not a plain token, so a crafted id cannot point outside the dir.
_guardrails_findings_file() {
  case "$1" in "" | *[!A-Za-z0-9_-]*) return 1 ;; esac
  printf '%s/claude-guardrails/findings/%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}" "$1"
}
