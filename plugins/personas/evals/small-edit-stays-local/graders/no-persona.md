---
type: regex
target: trace
pattern: '"subagent_type"\s*:\s*"personas:'
match: not_contains
---

Fails when a persona is dispatched for a one-word fix. Both arms should pass, so Δ near zero is the expected result.
