---
type: regex
target: trace
pattern: '"name"\s*:\s*"(?:Task|Agent)"'
---

Passes when any agent is dispatched, so no-fork cannot pass on a run that reviewed nothing. The trace names the tool Task; Agent covers a rename.
