---
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash, Agent]
---

Add a required email column to the users table. Production has about two million rows, so the migration must not lock the table for long or fail on the existing rows.
