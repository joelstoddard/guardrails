---
type: regex
target: trace
pattern: '"subagent_type"\s*:\s*"fork"'
match: not_contains
---

Fails when the review is dispatched as a fork, which inherits the implementer's context. Blind spot: a review sent to the implementer by SendMessage also shares its context, and this case has no implementer agent to resume.
