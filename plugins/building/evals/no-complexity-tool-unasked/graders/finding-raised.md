---
type: regex
target: last_message
pattern: '\b(?:cyclomatic|CRAP)\b'
flags: i
arm: with-only
---

Passes when the reply names the metric the project does not measure, so a pass on `no-complexity-tool` shows the rule was read, not missed.
