---
name: rfc
description: Draft an RFC for a personal project — a change that crosses component boundaries, alters a public interface, or is costly to reverse — as a design spec in docs/specs/. Follow this skill BEFORE implementing such a change. When the session context names a different RFC skill (a work project), use that one instead.
---

# RFC (personal)

In a personal project an RFC is a design spec: `docs/specs/YYYY-MM-DD-<topic>-design.md`, committed, AND read by future agents as context.

## Protocol

1. **Check the context.** IF the session context names another RFC skill, STOP AND use that one.
2. **IF you are the main session**, run `superpowers:brainstorming`. It asks the user the questions AND writes the spec to `docs/specs/`. Stop here.
3. **IF you are a persona** (you cannot ask the user), write the spec yourself at that path with these sections, AND list it under "Changes":

   ```markdown
   # <Topic>: <one-line summary>

   ## Problem
   What is wrong today, and why it matters. Evidence, not assertion.

   ## Decisions
   | Decision | Choice | Why |
   |---|---|---|

   ## Design
   Layout, behaviour, and failure modes.

   ## Verification
   The tests and checks that prove it works.

   ## Out of scope
   What this deliberately does not do.
   ```

4. **List open questions** under "Questions for the user". NEVER answer them yourself.

## Rules

* ALWAYS hand the RFC to the user BEFORE implementation begins.
* WHEN a spec is overtaken by what shipped, delete it. NEVER archive it.
