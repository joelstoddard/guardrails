---
name: project-memory
description: Record repo-local lessons and location breadcrumbs so the next contributor or agent does not repeat the mistake or the wrong first guess. Follow this skill after a mistake worth not repeating, and whenever a search misses in the first place you looked. Check it before acting in an unfamiliar area of a repo.
allowed-tools: Read, Write, Glob, Grep
---

This skill is for lessons about **this repo**. A lesson about a skill's own guidance belongs in `guardrails:self-improvement` instead.

## Storage

`.claude/docs/lessons/<slug>.md`, one file per lesson. A directory, not one document, so entries stay independently greppable and two contributors adding lessons never conflict. Slug is kebab-case from the trigger situation.

```markdown
---
kind: lesson
date: 2026-09-07
trigger: about to run `stow .` from inside a worktree
---

# Never re-stow from a worktree

**Cost:** overwrote every ~/.config symlink to point at the worktree.
**Do instead:** targeted `ln -s` for the specific files under test.
```

## Two record kinds

- `kind: lesson` — a mistake worth not repeating, by user or agent. Needs **Cost** and **Do instead**.
- `kind: breadcrumb` — where something actually lives. Needs **Looked in** and **Actually in**. Written when a search missed on the first guess.

## The breadcrumb protocol

When searching for something and the first place you look does not have it:

1. Note where you looked. Keep searching — do not write anything yet.
2. On finding it, write a breadcrumb recording **both** locations.

The wrong guess is the valuable half. It is what the next agent will also guess, and it is what makes the note findable — a breadcrumb filed only under the right answer is one nobody searching will hit.

Do not write a breadcrumb when the first guess was right, and do not write one for something the repo's own docs already state plainly.

## Reading

Before acting in an unfamiliar area, glob `.claude/docs/lessons/*.md` and read the `trigger` frontmatter lines. Triggers are situations, so this is a cheap match against what you are about to do.

## Rules

- Never put a secret, credential, hostname, or customer name in a lesson.
- One lesson per file. Update an existing file rather than adding a near-duplicate.
- Record the situation and the cost, not a narrative of the session.
- The ignore pattern for this directory lives in the repo's `.config/git/ignore`, and entries are local only once that file is the active global ignore — until then a new lesson shows up as an untracked file. So never stage a lesson file into an unrelated commit; it is not part of the change being committed. When the team is ready to share them, commit the directory deliberately, on its own.
- Do not write breadcrumb comments into unrelated source files. The lessons directory is the place, precisely so that recording a lesson never pollutes a diff.
