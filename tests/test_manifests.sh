#!/usr/bin/env bash
# Validator warnings are defects, except missing versions: installs track commits instead.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/helper.sh"
ROOT="$(cd "$DIR/.." && pwd)"
# A marketplace reports a plugin's missing version as "plugins[0] plugin.json → version".
CLEAN='[.. | objects | .errors? // empty | .[]] == [] and [.. | objects | .warnings? // empty | .[] | select(.path | test("(^|→ )version$") | not)] == []'

for target in "$ROOT" "$ROOT"/plugins/*; do
  claude plugin validate --json "$target" | jq -e "$CLEAN" >/dev/null \
    || { echo "  FAIL [${target#"$ROOT"}]: validator reports errors or warnings"; FAILS=1; }
done

versions="$(jq -r '.. | objects | select(has("version")) | .version' \
  "$ROOT/.claude-plugin/marketplace.json" "$ROOT"/plugins/*/.claude-plugin/plugin.json)"
assert_eq "" "$versions" "no version pins"

assert_eq '["building","recording"]' "$(jq -c '.dependencies' "$ROOT/plugins/personas/.claude-plugin/plugin.json")" \
  "personas depends on building and recording"

# A hook script that no hooks.json entry runs is a guard that silently stopped.
for s in "$ROOT"/plugins/*/hooks/scripts/*.sh; do
  jq -e --arg s "/hooks/scripts/$(basename "$s")" '[.. | objects | select(has("command")) | .command | select(contains($s))] != []' \
    "${s%/scripts/*}/hooks.json" >/dev/null || { echo "  FAIL [${s#"$ROOT"/}]: not run by its plugin's hooks.json"; FAILS=1; }
done

# Every script hook must run from a plugin root that contains a space.
SPACED="$(scratch_dir)/with space"
mkdir -p "$SPACED"
for p in "$ROOT"/plugins/*; do
  name="$(basename "$p")"; cp -R "$p" "$SPACED/$name"
  while IFS= read -r cmd; do
    CLAUDE_PLUGIN_ROOT="$SPACED/$name" bash -c "$cmd" </dev/null >/dev/null 2>&1; rc=$?
    case "$rc" in 126|127) echo "  FAIL [$name]: did not run from a spaced path (rc=$rc): $cmd"; FAILS=1 ;; esac
  done < <(jq -r '.. | objects | select(has("command")) | .command | select(contains("/hooks/scripts/"))' "$p/hooks/hooks.json")
done

finish "manifests"
