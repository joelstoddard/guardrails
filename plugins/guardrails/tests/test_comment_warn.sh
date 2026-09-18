#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/helper.sh"
S="$DIR/../hooks/scripts/comment-warn.sh"
TMP="$(mktemp -d)"

# write <name> <content> → prints a PostToolUse payload for a Write of that file
write() {
  printf '%s' "$2" > "$TMP/$1"
  jq -n --arg f "$TMP/$1" --arg c "$2" '{tool_input:{file_path:$f,content:$c}}'
}

over="# The queue drops messages. The breaker opens after ten failures. A larger value
# opens it for every worker. Use the design doc instead.
LIMIT = 3"
run_hook "$S" "$(write over.py "$over")"
assert_rc 0 "a long comment never blocks"
assert_out "additionalContext" "warning emitted as JSON"
assert_out "4 sentences" "counts the sentences"
assert_out "over.py:1" "reports file and line"

under="# All forty workers share one breaker. See docs/design/retry.md
LIMIT = 3"
run_hook "$S" "$(write under.py "$under")"
assert_rc 0 "two sentences allowed"
assert_eq "" "$OUT" "two sentences stay silent"

# Markdown headings are not comments — the hook must ignore text formats entirely
run_hook "$S" "$(write notes.md "$over")"
assert_eq "" "$OUT" "markdown ignored"

# A URL is not a // comment: only a line starting with the marker counts
url='u = "https://a.example. https://b.example. https://c.example. x"'
run_hook "$S" "$(write url.js "$url")"
assert_eq "" "$OUT" "mid-line marker ignored"

# Abbreviations and versions must not inflate the count
abbr="// Pin to 0.6.1 for the parser, e.g. the heredoc case. See the doc."
run_hook "$S" "$(write abbr.js "$abbr")"
assert_eq "" "$OUT" "abbreviations and versions are not sentence ends"

# Separate blocks are counted separately, not merged across code
split="# One. Two.
X = 1
# Three. Four."
run_hook "$S" "$(write split.py "$split")"
assert_eq "" "$OUT" "blocks split by code are counted apart"

rm -rf "$TMP"
finish "comment-warn"
