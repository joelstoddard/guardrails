---
max_turns: 20
allowed_tools: [Read, Glob, Grep, Skill, Bash]
---

We've decided greet.sh takes the name only from its first argument, never from a GREET_NAME environment variable. The install script calls it from a clean environment, so an environment variable would silently never be set there. Record this decision in the repo.
