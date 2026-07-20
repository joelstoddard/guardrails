#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/helper.sh"
S="$DIR/../hooks/scripts/lint-warn.sh"
json() { printf '{"cwd":"%s","tool_input":{"command":"%s"}}' "$1" "$2"; }

# Failing lint on commit → NEVER blocks (rc 0) but emits a warning on stdout
rf="$(make_repo main)"; git -C "$rf" switch -q -c nbc-1-x
printf '## Commands\n- **Lint:** `false`\n' > "$rf/AGENTS.md"
run_hook "$S" "$(json "$rf" "git commit -m x")"
assert_rc 0 "lint failure never blocks"
assert_out "additionalContext" "warning emitted as JSON"
assert_out "Lint" "warning mentions lint"

# Passing lint → silent allow
rp="$(make_repo main)"; git -C "$rp" switch -q -c nbc-2-y
printf '## Commands\n- **Lint:** `true`\n' > "$rp/AGENTS.md"
run_hook "$S" "$(json "$rp" "git commit -m x")"
assert_rc 0 "passing lint allowed"

finish "lint-warn"
