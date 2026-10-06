---
max_turns: 20
allowed_tools: [Read, Glob, Grep, Skill, Bash]
---

greet.sh breaks when the name contains a newline: the line it appends to /tmp/greet.log gets split in two. I don't have time to fix it now. File an issue for it.
