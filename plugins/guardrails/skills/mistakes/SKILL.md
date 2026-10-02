---
name: mistakes
description: Draft the broadcast for a mistake or incident — what happened, how it has been fixed, how we will prevent it. Follow this skill whenever something went wrong that someone else should hear about — a production incident, a broken build or release, or your own mistake (a bad push, a deleted file, a false "done", a wrong claim). In a personal project it is the whole post-mortem. Drafts only; never sends.
---

# Mistakes

A mistake is told once, plainly, with the fix and the constraint that stops it recurring. You write the draft. The user sends it.

## Protocol

1. **Stop the impact FIRST.** IF impact is ongoing, propose the mitigation (rollback, flag off, revert) BEFORE writing anything. Execute it ONLY with explicit approval.
2. **Gather evidence.** Collect the actual commands, outputs, commits, AND timestamps. NEVER reconstruct them from memory.
3. **Draft the broadcast** with exactly these three headings:

   ```markdown
   ## What happened
   Impact first: who or what was affected, and for how long. Then a short timeline.
   Mark each statement **known**, **suspected**, or **not yet verified**.

   ## How it has been fixed
   The change (commit, PR, or action), and the evidence it worked: the regression test
   that fails without the fix and passes with it, the command, and its result.

   ## How we will prevent it
   Each prevention names a deterministic constraint: a test, hook, rule, gate,
   permission, or alert.
   ```

4. **Name the audience** above the draft: who it is for, AND what it needs to achieve.
5. **Hand it over.** Show the full draft to the user. NEVER send, post, OR publish it.
6. **Record the lesson.** A lesson about this repo → `guardrails:project-memory`. A lesson about a skill → `guardrails:self-improvement`.
7. **Track the prevention.** Each prevention NOT built in this change is a finding. File it with `guardrails:track-findings`.

## Rules

* NEVER write "be more careful" as a prevention. A prevention a machine does not check is NOT a prevention.
* NEVER assign blame to a person. Describe the system that allowed the mistake.
* NEVER present a hypothesis as the root cause.
* NEVER declare it resolved while a prevention is neither in place NOR tracked.
* IF the session context names a post-mortem skill AND the incident is above the project's severity threshold, ALSO draft that post-mortem. IF the threshold is undefined, ask.
