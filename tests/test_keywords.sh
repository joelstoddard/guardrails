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

# An all-capitals word reads as a keyword, so each one in a rules file is a keyword conduct.md defines (BCP 14's or
# the project extension's), a term the rules define, or an acronym. Emphasis is lower-case (#122).
KEYWORDS=" MUST NOT REQUIRED SHALL SHOULD RECOMMENDED MAY OPTIONAL IF WHEN WHERE WHILE AND OR BEFORE THEN FIRST LASTLY ONLY EVERY UNLESS OTHERWISE "
TERMS=" EDIT CHANGE RELEASE STANDING PERSONAL WORK DONE PARTIAL BLOCKED ADR API BCP CI CLI CRAP DRY ISP KISS LSP MCP RFC SRP TDD URL "
while IFS=: read -r file line word; do
  case "$KEYWORDS$TERMS" in *" $word "*) continue ;; esac
  echo "  FAIL [${file#"$ROOT"/}:$line]: $word is undefined; define it in conduct.md \"Keywords\" or lower-case it"
  FAILS=1
done < <(grep -noE '\b[A-Z]{2,}\b' "$ROOT"/plugins/*/rules/*.md)

# A keyword accepted above but no longer defined in conduct.md would pass undefined. BCP 14's are quoted there, and
# the extension's are labels: "IF / WHEN: …", "AND: …".
section="$(awk '/^### Keywords/ { f = 1; next } /^#/ { f = 0 } f' "$ROOT/plugins/building/rules/conduct.md")"
for w in $KEYWORDS; do
  grep -qE "\"$w\"|\\b$w( / [A-Z]+)*:" <<< "$section" \
    || { echo "  FAIL [conduct.md]: $w is accepted as a keyword but \"Keywords\" does not define it"; FAILS=1; }
done

finish "keywords"
