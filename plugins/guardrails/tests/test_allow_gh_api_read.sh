#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/helper.sh"
S="$DIR/../hooks/scripts/allow-gh-api-read.sh"

json() { jq -nc --arg c "$1" '{tool_input:{command:$c}}'; }
# allows <cmdline> <label> — the hook must answer with an allow decision.
allows() { run_hook "$S" "$(json "$1")"; assert_rc 0 "$2"; assert_out '"permissionDecision":"allow"' "$2"; }
# asks <cmdline> <label> — the hook must stay silent so the ask rule decides.
asks()   { run_hook "$S" "$(json "$1")"; assert_rc 0 "$2"; assert_eq "$OUT" "" "$2"; }

# --- plain GETs, in every spelling gh accepts for the method ---
allows 'gh api repos/o/r/pulls/1'              "implicit GET"
allows 'gh api -X GET /user'                   "-X GET"
allows 'gh api --method GET repos/o/r/issues'  "--method GET"
allows 'gh api --method=GET repos/o/r'         "--method=GET"
allows 'gh api -XGET repos/o/r'                "-XGET"

# --- read modifiers, including the one shape the old settings hook allowed ---
allows "gh api --method GET repos/o/r/pulls/1/comments --paginate --jq '.[] | .body'" \
  "PR review comments, paginated, jq"
allows "gh api repos/o/r/pulls -H 'Accept: application/vnd.github+json' --jq '.[] | select(.user.login == \"x\") | .number'" \
  "header, then jq with pipes, parens and inner quotes"
allows 'gh api repos/o/r/contents/README.md --jq ".content"' "double-quoted jq value"
allows "gh api 'repos/o/r/pulls?state=open&per_page=100'"    "quoted query string with &"
allows 'gh api repos/o/r/pulls --paginate --slurp -i --silent --cache 1h -t "{{.n}}"' \
  "the remaining read flags"

# --- writes: a method other than GET, or anything that gives the request a body ---
asks 'gh api -X POST repos/o/r/issues/1/comments -f body=hi' "-X POST"
asks 'gh api --method PATCH repos/o/r/issues/1'            "--method PATCH"
asks 'gh api --method=DELETE repos/o/r/issues/1'           "--method=DELETE"
asks "gh api -X 'POST' repos/o/r/issues"                   "quoted method"
asks 'gh api repos/o/r/issues -f body=x'                   "-f implies POST"
asks 'gh api repos/o/r/issues -F body=@file'               "-F implies POST"
asks 'gh api repos/o/r/issues --input body.json'           "--input implies POST"
asks "gh api graphql -f query='{viewer{login}}'"           "graphql needs -f, stays a prompt"

# --- the shell must not run anything else alongside the read ---
asks 'gh api repos/o/r/pulls?state=open&per_page=100' "unquoted & backgrounds gh and runs per_page=100"
asks 'gh api repos/o/r/pulls | jq .'                  "pipe"
asks 'gh api repos/o/r && rm -rf x'                   "chain"
asks 'gh api repos/o/r; gh api -X DELETE repos/o/r/x' "semicolon"
asks "$(printf 'gh api repos/o/r\ngh api -X DELETE repos/o/r/x')" "newline"
asks 'gh api repos/o/r > out.json'                    "redirect"
asks 'gh api "repos/$(id)/r"'                         "command substitution in double quotes"
asks 'gh api repos/o/r `id`'                          "backticks"
asks "gh api repos/o/r \\'; id; \\'"                  "escaped quote does not open a quoted span"
asks "gh api 'repos/o/r"                              "unterminated quote"

# --- shapes outside the allowlist fall through rather than being judged ---
asks 'gh api https://example.com/x'                "full URL"
asks 'gh api --hostname ghe.example.com repos/o/r' "--hostname"
asks 'gh api repos/o/r --unknown-flag'             "unknown flag"
asks 'gh api repos/o/r repos/o/r2'                 "two endpoints"
asks 'GH_TOKEN=x gh api repos/o/r'                 "environment prefix"
asks 'gh pr view 1'                                "not gh api"
run_hook "$S" '{"tool_input":{}}'; assert_rc 0 "missing command"; assert_eq "$OUT" "" "missing command"

finish "allow-gh-api-read"
