#!/usr/bin/env bash
# The rules use BCP 14 keywords, so an all-capitals ALWAYS or NEVER is undefined.
# See docs/specs/2026-10-06-rfc2119-keywords-design.md.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/helper.sh"
ROOT="$(cd "$DIR/.." && pwd)"

# An empty or moved plugins tree would otherwise pass.
[ -n "$(find "$ROOT/plugins" -name '*.md' -print -quit)" ] || { echo "  FAIL: no markdown under plugins/"; FAILS=1; }

hits="$(grep -rnowE 'ALWAYS|NEVER' "$ROOT/plugins" || true)"
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  echo "  FAIL [${hit#"$ROOT"/}]: not a BCP 14 keyword; use MUST or MUST NOT"
  FAILS=1
done <<< "$hits"

# The spec maps a rule with its own escape clause to SHOULD. A MUST is absolute, so an escape clause contradicts it.
escapes="$(grep -rnoE 'MUST( NOT)?[^.;]*(without (good )?reason|without warrant|where practical|where possible|if possible|\bprefer\b)' "$ROOT/plugins" || true)"
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  echo "  FAIL [${hit#"$ROOT"/}]: a MUST with its own escape; use SHOULD and drop the escape"
  FAILS=1
done <<< "$escapes"

finish "keywords"
