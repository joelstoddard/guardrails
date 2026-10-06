---
type: regex
target: trace
pattern: '"subagent_type"\s*:\s*"personas:data-engineer"'
---

Passes when Claude dispatches the data-engineer persona. Without the plugin no such agent exists, so that arm cannot name it.
