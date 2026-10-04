#!/usr/bin/env bash
# Rules reach context through hooks, and hook output over 10,000 characters arrives as a 2,000-character preview.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/helper.sh"
ROOT="$(cd "$DIR/.." && pwd)"

actual="$(cd "$ROOT/plugins" && ls -1 */rules/*.md 2>/dev/null | tr '\n' ' ')"
assert_eq "building/rules/conduct.md building/rules/engineering.md personas/rules/delegation.md recording/rules/findings.md " \
  "$actual" "the four rules files exist"

for f in "$ROOT"/plugins/*/rules/*.md; do
  [ -e "$f" ] || continue
  n="$(wc -m < "$f" | tr -d ' ')"
  [ "$n" -lt 10000 ] || { echo "  FAIL [${f#"$ROOT"/}]: $n characters, the cap is 10,000"; FAILS=1; }
done

# Run each rules hook as Claude Code would, from a plugin root that contains a space.
SPACED="$(mktemp -d)/with space"
trap 'rm -rf "$(dirname "$SPACED")"' EXIT
mkdir -p "$SPACED"
for f in "$ROOT"/plugins/*/rules/*.md; do
  rel="${f#"$ROOT"/plugins/}"; plugin="${rel%%/*}"; name="$(basename "$f")"
  [ -d "$SPACED/$plugin" ] || cp -R "$ROOT/plugins/$plugin" "$SPACED/$plugin"
  for e in SessionStart SubagentStart; do
    cmds="$(jq -r --arg e "$e" --arg n "rules/$name" \
      '[.hooks[$e][]?.hooks[]?.command | select(contains($n))] | .[]' "$ROOT/plugins/$plugin/hooks/hooks.json")"
    count="$(printf '%s' "$cmds" | grep -c . || true)"
    [ "$count" = 1 ] || { echo "  FAIL [$plugin/$name]: $count $e entries, want 1"; FAILS=1; continue; }
    CLAUDE_PLUGIN_ROOT="$SPACED/$plugin" bash -c "$cmds" \
      | jq -e --arg e "$e" --arg r "$SPACED/$plugin" --rawfile f "$f" \
        '.hookSpecificOutput.hookEventName == $e and .hookSpecificOutput.additionalContext == ($f | gsub("\\$\\{CLAUDE_PLUGIN_ROOT\\}"; $r))' \
        >/dev/null || { echo "  FAIL [$plugin/$name]: $e output does not match the file"; FAILS=1; }
  done
done

finish "rules"
