#!/usr/bin/env bash
# Skill and agent names carry their plugin's prefix, and nothing points at a file that no longer exists.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/helper.sh"
ROOT="$(cd "$DIR/.." && pwd)"

stale="$(grep -rnE '(^|[^-[:alnum:]])guardrails:([a-z]|`)|~/\.claude/agents|~/\.claude/rules/(core|delegation)\.md|(^|[^/[:alnum:]_-])core\.md' "$ROOT/plugins")"
assert_eq "" "$stale" "no stale skill names or rule paths"

while IFS= read -r ref; do
  plugin="${ref%%:*}"; name="${ref#*:}"
  [ -f "$ROOT/plugins/$plugin/skills/$name/SKILL.md" ] || [ -f "$ROOT/plugins/$plugin/agents/$name.md" ] \
    || { echo "  FAIL [$ref]: no such skill or agent"; FAILS=1; }
done < <(grep -rhoE '(building|recording|personas):[a-z][a-z0-9-]*' "$ROOT/plugins" | sort -u)

finish "references"
