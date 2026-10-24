#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/helper.sh"
. "$DIR/../plugins/recording/lib/findings.sh"

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
1. Cache never expires #12

Next: run these.
1. `make clean`
2. `make test`')"
assert_eq "Cache never expires #12" "$OUT" "a plain line after the list ends the section"

OUT="$(_guardrails_findings '### Findings outside scope
These are new:
- Retries are unbounded')"
assert_eq "Retries are unbounded" "$OUT" "a plain line before the first item does not end the section"

OUT="$(_guardrails_findings '### Findings outside scope
1. Cache never expires because
the TTL is unset.
2. Retries are unbounded')"
assert_eq "Cache never expires because the TTL is unset.
Retries are unbounded" "$OUT" "an unindented line straight after an item continues it"

OUT="$(_guardrails_findings '### Findings outside scope
1. Cache never expires
> quoted log line
| a | table |
<!-- note -->
---
2. Retries are unbounded')"
assert_eq "Cache never expires
Retries are unbounded" "$OUT" "quotes, tables, comments and rules between items keep the section open"

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

_guardrails_listing '### Findings outside scope
None.' && r=yes || r=no
assert_eq "yes" "$r" "a findings heading is a findings list, even an empty one"
_guardrails_listing '**Findings outside scope:**' && r=yes || r=no
assert_eq "yes" "$r" "a bold findings heading is a findings list"
_guardrails_listing '### Notes and *findings outside scope*' && r=yes || r=no
assert_eq "yes" "$r" "a heading with emphasis inside is a findings list"
_guardrails_listing '**Findings outside scope** are held until the end.' && r=yes || r=no
assert_eq "no" "$r" "bold words in a sentence are not a findings list"
_guardrails_listing 'Step 2 of 3 done.' && r=yes || r=no
assert_eq "no" "$r" "no heading, no findings list"
_guardrails_listing "$fenced" && r=yes || r=no
assert_eq "no" "$r" "a fenced heading is not a findings list"

OUT="$(_guardrails_findings '**Findings outside scope**:
- colon after the bold')"
assert_eq "colon after the bold" "$OUT" "bold heading with the colon outside"

OUT="$(_guardrails_findings '### Findings outside scope
  - indented one
  - indented two
    with detail')"
assert_eq "indented one
indented two with detail" "$OUT" "indented items: the first item's indent is the top level"

OUT="$(_guardrails_findings '### Findings outside scope
- top item
  - nested detail')"
assert_eq "top item - nested detail" "$OUT" "a nested bullet continues its item"

four='````markdown
```
### Findings outside scope
- example inside
```
````
### Findings outside scope
- real one'
OUT="$(_guardrails_findings "$four")"
assert_eq "real one" "$OUT" "a 4-backtick fence holds a 3-backtick fence"

unclosed='### Findings outside scope
- one
```
- two'
OUT="$(_guardrails_findings "$unclosed")"
assert_eq "one
two" "$OUT" "an unclosed fence hides nothing: the parser fails closed"

for empty in 'None found.' 'No findings.' 'Nothing to report.' '*None*' '(none)' 'None — all in scope.' 'N/A' 'nothing'; do
  OUT="$(_guardrails_findings "### Findings outside scope
- $empty")"
  assert_eq "" "$OUT" "empty list phrased '$empty'"
done
OUT="$(_guardrails_findings '### Findings outside scope
- None of the retries are bounded')"
assert_eq "None of the retries are bounded" "$OUT" "a finding that starts with None is still a finding"

tracked='### Findings outside scope
- Cache expiry https://github.com/o/r/issues/12
- Retry bound #13
- Lint gap o/r#14.
- Work item https://linear.app/acme/issue/ENG-9/fix-it
- Not wanted (declined)
- Shared repo, waiting on the user (asked)
- PR #85 needs two lines in home/claude.nix
- Strings use UTF-8
- Ends with #1 priority bug
- Fixed already in PR #85
- Fixed already in PR o/r#86.
- Waiting on the user (Asked)
- Not wanted (DECLINED)'
OUT="$(_guardrails_untracked "$tracked")"
assert_eq "PR #85 needs two lines in home/claude.nix
Strings use UTF-8
Ends with #1 priority bug
Fixed already in PR #85
Fixed already in PR o/r#86." "$OUT" "only an end-of-line issue reference or marker tracks: not mid-line #N, not a PR, any case"

finish "findings"
