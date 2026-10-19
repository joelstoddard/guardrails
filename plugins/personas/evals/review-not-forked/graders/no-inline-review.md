---
type: regex
target: trace
pattern: '"name"\s*:\s*"Skill"\s*,\s*"input"\s*:\s*\{\s*"skill"\s*:\s*"(?:[\w-]+:)?(?:requesting-)?code-review".*"parent_tool_use_id"\s*:\s*null'
match: not_contains
---

Fails when the main session runs a code-review skill itself, reviewing in the implementer's context. A reviewer subagent running the same skill carries a parent_tool_use_id, so it passes.
