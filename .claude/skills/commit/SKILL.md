---
name: commit
description: Create atomic conventional commits. Follow this skill whenever committing code — main agents show a proposed commit for user approval, sub-agents commit as they go and surface a summary in their return value.
allowed-tools: Bash(git *)
---

## Current state

- Status: !`git status --short`
- Diff: !`git diff`

## Rules

### Never push
NEVER run `git push`. Pushing is always the user's decision.

### Atomic changes
Each commit must be the smallest meaningful unit of change. If a diff touches two unrelated concerns, split into separate commits. One logical change per commit.

### Test before committing
Run relevant tests, linters, or validation first. If tests fail, fix before committing. If no automated tests exist, verify manually (e.g. `zsh -n` for shell scripts, config syntax checks).

### Commit message format

Follow [Conventional Commits v1.0.0](https://www.conventionalcommits.org/en/v1.0.0/).

```
<type>[optional scope][optional !]: <description>

[optional body]

[optional footer(s)]
```

**Types:** `feat`, `fix`, `refactor`, `chore`, `docs`, `style`, `test`, `build`, `ci`, `perf`

**Scope:** Single atomic identifier only — NEVER comma-separate scopes. If a change spans two scopes it isn't atomic; split the commit.
- Bad: `fix(auth, session): ...`
- Good: split into `fix(auth): ...` and `fix(session): ...`

**Breaking changes:** use `!` before colon and/or `BREAKING CHANGE:` footer.

**Message guidelines:**
- Describe the *why*, not the *what* — the diff shows what changed
- Bad: `fix(.zshrc): change -z to -f for brew check`
- Good: `fix(.zshrc): ensure Homebrew is detected on macOS`
- Subject line under 72 characters
- Imperative mood: "add", "fix", "ensure" — not "added", "fixed", "ensures"

## Workflow

### Main agent (direct user interaction)

1. Identify the smallest atomic unit of change to commit.
2. Run tests/validation for that change.
3. Present to the user: files to stage, proposed commit message, what was validated.
4. Wait for explicit approval before running `git commit`.
5. Stage only approved files and commit.
6. If more changes remain, repeat from step 1.

### Sub-agent (dispatched via Agent tool)

Commits serve as both **safety net** (atomic changes can be reverted surgically without losing surrounding valuable work) and **narrative** (history captures rationale so developers can understand how and why the code evolved).

Commit as you go — not at the end:

1. After each self-contained unit of change, run tests/validation and commit immediately.
2. Do not batch — commit each logical step as it is completed.
3. Write messages that capture *why*, not just *what* — this narrative is what future developers and agents rely on.
4. In your return value include a **Commits made** section: hash, message, and files changed for each commit.
5. The calling agent can revert individual commits if needed; the history is the audit trail.
