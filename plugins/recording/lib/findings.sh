#!/usr/bin/env bash
# findings.sh — read the "Findings outside scope" list out of a report or final message.
#
# Usage: _guardrails_findings "<text>"  → one finding per line, continuation lines joined
#        _guardrails_untracked "<text>" → the findings whose line does not end with a reference

# A reference counts only at the end of the item, so a mid-sentence "PR #85" is not one.
# Matched against lowercased text, as is the PR reference, which marks a pull request, not an issue.
_GUARDRAILS_TRACKED_RE='(github\.com/[^[:space:]]+/issues/[0-9]+|linear\.app/[^[:space:]]+/issue/[a-z0-9-]+[^[:space:]]*|(^|[^a-z0-9&])#[0-9]+|[a-z0-9_.-]+/[a-z0-9_.-]+#[0-9]+|\((declined|asked)\))[]).>]*[[:space:]]*$'
_GUARDRAILS_PR_RE='pr[[:space:]]+([a-z0-9_.-]+/[a-z0-9_.-]+)?#[0-9]+[]).>]*[[:space:]]*$'

# _guardrails_unfence <text> → the text without its closed code fences. A fence closes only on the
# same character, at least as long; an unclosed fence stays as text, so nothing after it is hidden.
_guardrails_unfence() {
  printf '%s\n' "$1" | awk '
    function run(s) { match(s, /^[[:space:]]*(```+|~~~+)/); s = substr(s, RSTART, RLENGTH); sub(/^[[:space:]]*/, "", s); return s }
    { line[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) {
        o = run(line[i])
        if (o == "") { print line[i]; continue }
        for (j = i + 1; j <= NR; j++) {
          c = run(line[j])
          if (substr(c, 1, 1) == substr(o, 1, 1) && length(c) >= length(o) && line[j] ~ /^[[:space:]]*(`+|~+)[[:space:]]*$/) break
        }
        if (j <= NR) i = j; else print line[i]
      }
    }'
}

_guardrails_findings() {
  _guardrails_unfence "$1" | awk '
    function flush() { if (item != "") print item; item = "" }
    # Emphasis, parentheses and a dashed reason do not make an empty list a finding.
    function empty(s) {
      s = tolower(s); gsub(/[*_()]/, "", s); sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s)
      return s ~ /^((none|nothing)( found| to report)?|no findings( outside scope)?|n\/a)[.!]?$/ ||
        s ~ /^(none|nothing|n\/a)[[:space:]]+(-|–|—)[[:space:]]/
    }
    /^[[:space:]]*#+[[:space:]]/ || /^[[:space:]]*\*\*[^*]+\*\*[[:space:]:]*$/ {
      flush(); insec = (tolower($0) ~ /findings outside scope/); base = -1; next
    }
    !insec { next }
    # The first item sets the top level; a deeper bullet continues the item above it.
    /^[[:space:]]*([-*+]|[0-9]+[.)])[[:space:]]+/ {
      match($0, /^[[:space:]]*/)
      if (base < 0) base = RLENGTH
      if (RLENGTH <= base) {
        flush(); line = $0; sub(/^[[:space:]]*([-*+]|[0-9]+[.)])[[:space:]]+/, "", line)
        if (!empty(line)) item = line
        next
      }
    }
    /^[[:space:]]+[^[:space:]]/ { if (item != "") { l = $0; sub(/^[[:space:]]+/, "", l); item = item " " l }; next }
    /^[[:space:]]*$/ { next }
    { flush() }
    END { flush() }'
}

# _guardrails_split tracked|untracked → of the findings on stdin, the ones that are (or are not) tracked.
# ENVIRON, not awk -v, carries the patterns, because -v would expand their backslashes.
_guardrails_split() {
  W="$1" T="$_GUARDRAILS_TRACKED_RE" P="$_GUARDRAILS_PR_RE" awk '{
    l = tolower($0); t = (l ~ ENVIRON["T"] && l !~ ENVIRON["P"])
    if (t == (ENVIRON["W"] == "tracked")) print
  }'
}

# _guardrails_handback <transcript> → the report a subagent handed back, IF its last assistant turn is a
# SubagentHandback call; last_assistant_message then holds nothing or earlier text. See issue #2.
_guardrails_handback() {
  [ -f "$1" ] || return 0
  tail -n 200 "$1" | jq -rs '[.[] | select(.type == "assistant")] | last | .message.content // []
    | map(select(.type == "tool_use" and .name == "SubagentHandback")) | last | .input.message // empty' 2>/dev/null
}

_guardrails_untracked() {
  _guardrails_findings "$1" | _guardrails_split untracked
}

# _guardrails_token <id> → succeeds only for a plain token, so a crafted id cannot point outside a dir.
_guardrails_token() {
  case "$1" in "" | *[!A-Za-z0-9_-]*) return 1 ;; esac
}

# _guardrails_pending_dir <session_id> → where SubagentStop keeps findings for the Stop gate, one file per subagent.
_guardrails_pending_dir() {
  _guardrails_token "$1" || return 1
  printf '%s/claude-guardrails/pending/%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}" "$1"
}
