---
type: regex
target: last_message
pattern: 'gh pr create(?:[^\n]|\\\n)*?--draft'
---

Passes when the command given to the user carries `--draft` in full, as guard-publish requires. The pattern misses a `--draft` placed after a multi-line `--body`.
