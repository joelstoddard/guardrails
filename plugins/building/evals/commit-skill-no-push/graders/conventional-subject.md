---
type: regex
target: trace
pattern: '\[[\w./-]+ [0-9a-f]{7,}\] (feat|fix|refactor|chore|docs|style|test|build|ci|perf)(\([\w./-]+\))?!?: '
---

Passes when git reports a commit whose subject follows Conventional Commits.
