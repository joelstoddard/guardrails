---
type: regex
target: last_message
pattern: '^\s*(?:[-*+]|\d+[.)])\s+[^\n]*(?:greet\.log|/tmp)[^\n]*(?:\(asked\)|\(declined\)|#\d+|/issues/\d+)[\]).>*]*\s*$'
flags: im
---

Passes when a list item about the /tmp log ends with an issue reference, (asked) or (declined).
