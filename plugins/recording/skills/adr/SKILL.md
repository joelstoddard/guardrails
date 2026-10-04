---
name: adr
description: Record a significant design decision in a personal project as a design doc in docs/design/<concept>.md, cited from the code that depends on it. Follow this skill when you make or change an architectural decision, choose between alternatives with real trade-offs, or need more than two sentences to explain why code is the way it is. When the session context names a different ADR skill (a work project), use that one instead.
---

# ADR (personal)

In a personal project an ADR is a design doc: `docs/design/<concept>.md`, named after the concept (NOT the change), AND cited from the code that depends on it.

## Protocol

1. **Check the context.** IF the session context names another ADR skill, STOP AND use that one.
2. **Look for an existing doc** on the concept in `docs/design/`. IF one exists, update it in place.
3. **Write it** with these sections. Drop a section ONLY WHEN it would be empty:

   ```markdown
   # <The concept, as a noun phrase>

   ## Problem
   ## The constraint
   ## Design
   ## Rejected alternatives
   ## Failure mode if you change this
   ```

4. **Cite it** from the code with a one-line comment, `See docs/design/<concept>.md`, at the place that depends on it (`guardrails:concise-comments`).

## Rules

* ALWAYS update a design doc in place WHEN its decision changes. NEVER leave a stale version alongside it, AND NEVER archive one. Git history keeps the old reasoning.
* ALWAYS state the alternatives rejected AND WHY.
