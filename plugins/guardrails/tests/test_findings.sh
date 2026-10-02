#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/helper.sh"
. "$DIR/../lib/findings.sh"

report='## Result: DONE
### Changes
- edited a.py
### Findings outside scope
- The cache never expires
  because the TTL is unset.
2. Retries are unbounded in client.go
### Questions for the user
- none'
OUT="$(_guardrails_findings "$report")"
assert_eq "The cache never expires because the TTL is unset.
Retries are unbounded in client.go" "$OUT" "bullets, numbers, continuation joined, section ends at next heading"

OUT="$(_guardrails_findings '### Findings outside scope
None.')"
assert_eq "" "$OUT" "prose None is no finding"

OUT="$(_guardrails_findings '### Findings outside scope
- None')"
assert_eq "" "$OUT" "bullet None is no finding"

OUT="$(_guardrails_findings '### Changes
- a change')"
assert_eq "" "$OUT" "absent section"

OUT="$(_guardrails_findings '**Findings outside scope:**
- bold heading works')"
assert_eq "bold heading works" "$OUT" "bold heading"

fenced='Here is the format:
```markdown
### Findings outside scope
- example item
```
Done.'
OUT="$(_guardrails_findings "$fenced")"
assert_eq "" "$OUT" "fenced block ignored"

tracked='### Findings outside scope
- Cache expiry https://github.com/o/r/issues/12
- Retry bound #13
- Lint gap o/r#14.
- Work item https://linear.app/acme/issue/ENG-9/fix-it
- Not wanted (declined)
- Shared repo, waiting on the user (asked)
- PR #85 needs two lines in home/claude.nix
- Strings use UTF-8
- Ends with #1 priority bug'
OUT="$(_guardrails_untracked "$tracked")"
assert_eq "PR #85 needs two lines in home/claude.nix
Strings use UTF-8
Ends with #1 priority bug" "$OUT" "only an end-of-line reference tracks; mid-line #N is untracked"

finish "findings"
