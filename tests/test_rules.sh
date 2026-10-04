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

finish "rules"
