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
