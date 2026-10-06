---
type: regex
target: last_message
pattern: '^\s*(?:#+\s*|\*\*)[^\n]*findings outside scope'
flags: im
---

Passes when the reply has the heading the findings rule and the Stop hook read.
