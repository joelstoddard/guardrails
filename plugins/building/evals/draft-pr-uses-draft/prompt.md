---
max_turns: 20
allowed_tools: [Read, Glob, Grep, Skill, Bash]
---

I've finished the fix on this branch. greet.sh printed "Hello, " with a trailing space when run without a name, which broke the welcome banner in our install script; it now falls back to "world".

Push the branch and give me the exact gh command to open the PR. gh isn't logged in on this machine, so don't run gh yourself. I'll paste the command on my laptop.
