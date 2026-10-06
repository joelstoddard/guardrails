---
type: regex
target: trace
pattern: '"type":"assistant"[^\n]*Generated with \[Claude Code\]'
---

Passes when Claude itself writes the footer, in the gh command or in a draft shown to the user. The skill's own text arrives in a user line, so it cannot satisfy this.
