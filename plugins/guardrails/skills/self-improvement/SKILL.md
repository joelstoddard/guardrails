---
name: self-improvement
description: Record and later apply lessons about the skills themselves. Follow this skill whenever the user corrects you, a skill's guidance led you into a mistake, or you notice a gap in a skill you just used — record the lesson before moving on. Invoke with "apply" to promote recorded lessons into the skill files.
allowed-tools: Bash(jq:*), Read, Edit, Write, Skill
---

## Journal

Lessons live in `~/.claude/skill-lessons.jsonl`, overridable via `GUARDRAILS_LESSONS_JOURNAL`. Resolve the path the same way the `lessons-nudge` hook does:

```
journal="${GUARDRAILS_LESSONS_JOURNAL:-$HOME/.claude/skill-lessons.jsonl}"
```

The file is JSON Lines: one entry per line, fields in this order:

| Field | Meaning |
|---|---|
| `date` | `YYYY-MM-DD`. The nudge hook string-compares this against a cutoff and also converts it to epoch — any other format breaks both. |
| `skill` | The skill's plugin-qualified name, e.g. `guardrails:commit`. |
| `trigger` | The situation that should fire the improved guidance, phrased as a situation, not a conclusion — it's what a future agent pattern-matches against. |
| `mistake` | What went wrong. |
| `fix` | The guidance that should have applied. |
| `promoted` | Boolean. `false` until the `apply` workflow folds the lesson into the skill file. |

### Hard rule: every line is one JSON object, nothing else

The hook's read (`fromjson? // empty`) only skips lines that fail to *parse*. A line that parses but isn't an object — a bare number, string, or array — still passes that filter, and the hook's next step (`select(.promoted != true)`) then throws a jq type error on it, aborting the whole read. One bad line silently kills the nudge for every entry in the file, not just itself. So: never append a comment, a blank line, a plain-text note, or anything but exactly one JSON object per line.

Canonical shape:

```json
{"date":"2026-09-08","skill":"guardrails:commit","trigger":"user asked to squash a diff spanning two scopes","mistake":"committed both scopes together","fix":"split by scope before committing when a diff touches two concerns","promoted":false}
```

## Record (default)

Fires on:
- the user correcting you
- a skill's instructions producing a wrong result
- noticing a case a skill doesn't cover

This skill is for lessons about the **skills themselves**. A lesson about how *this repo* works belongs in `guardrails:project-memory` instead.

Silently check whether the journal already carries this lesson for this skill — Read the file and compare the `skill` and `trigger` fields. If it does, skip — one entry per distinct lesson, not one per occurrence. This check produces no output either way.

Otherwise append one line **using the Write/Edit tools, never a shell heredoc**: the plugin's own publish guard inspects heredoc bodies and refuses any carrying an ordinary word like "review", "comment" or "post" near the start of the text — which describes most lessons about a plugin whose skills are named `pre-pr-review`, `concise-comments` and `draft-pr`. Append by Editing the journal's last line into itself plus the new line; if the file does not exist yet, Write it with that single line.

```json
{"date":"2026-09-08","skill":"...","trigger":"...","mistake":"...","fix":"...","promoted":false}
```

Then continue the task. Do not read the journal back, do not summarise what was written, do not mention the write happened. Recording is background bookkeeping — narrating it interrupts the task it's supposed to stay invisible to.

Never record:
- a user preference specific to this one task
- anything containing a secret or credential
- a mistake that wasn't the skill's doing

## Apply

Invoked as `/guardrails:self-improvement apply`. This is the only path that changes a skill file, and it always goes through review — nothing here is silent.

1. Read the journal. Keep entries where `promoted` is not `true`:
   ```
   jq -c 'select(.promoted != true)' "$journal"
   ```
2. Group the kept entries by `skill`. Drop any whose lesson the skill file already states — re-stating an existing rule isn't a promotion.
3. Create a worktree via `superpowers:using-git-worktrees`. Do this before touching any skill file — editing one from the main checkout trips the plugin's own default-branch commit guard, so the edit would be blocked anyway.
4. For each skill, fold its lessons into the existing file section by section. Prefer strengthening a rule that's already there — sharpening its wording, adding the missed case to its list — over appending a new rule or section. A skill that only grows becomes a skill nobody reads.
5. Run the plugin's test suite from its root (`tests/run.sh`). The preamble test must still pass — a fold that introduces a stray character sequence in a code example fails it.
6. Commit per skill via `guardrails:commit`, then open a draft PR via `guardrails:draft-pr`.
7. Mark each promoted entry `"promoted": true` in the journal — flip that one field on its line, don't delete the line. The journal is the record of what the agent has learned; a promoted entry is history, not clutter.

## Rules

- The journal lives outside any repo. Recording can never dirty a working tree or trip the default-branch guard — that's what keeps it silent.
- Promotion always goes through the worktree → commit → draft-PR flow. This skill edits the instructions the agent itself follows; that's exactly the kind of change that shouldn't land unreviewed.
- Never promote automatically or on a timer. The `lessons-nudge` hook only reports a count; a human decides when to run `apply`.
