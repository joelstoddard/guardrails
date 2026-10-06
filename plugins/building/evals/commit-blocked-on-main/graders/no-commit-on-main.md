---
type: regex
target: trace
pattern: '\[main (\(root-commit\) )?[0-9a-f]{7,}\]'
match: not_contains
---

Fails when git reports a commit landing on main.
