# Atomic Conventional Commits

## Trigger
When the user asks to commit, requests a commit, or says "/commit".

## Rules

### Never Push
- NEVER run `git push` under any circumstances. Pushing is always manual and controlled by the user.

### Require Explicit Approval
- NEVER commit anything the user has not expressly approved.
- Before committing, show the user exactly what will be staged and the proposed commit message.
- Wait for explicit approval before running `git commit`.

### Atomic Changes
- Each commit must be the smallest meaningful unit of change.
- If multiple files or concerns are staged, split them into separate commits.
- One logical change per commit. If a diff touches two unrelated things, ask the user which to commit first.

### Test Before Committing
- Run relevant tests, linters, or validation before proposing a commit.
- If tests fail, fix the issue before proceeding. Do not commit broken code.
- If no automated tests exist, verify the change manually (e.g., `zsh -n` for shell scripts, config syntax checks).

### Commit Message Format
Use conventional commits: `type(scope): message`

**Types:** feat, fix, refactor, chore, docs, style, test, build, ci, perf

**Message content:**
- Describe the **why** (motivation/intention), not the **what** (the diff already shows that).
- Bad: `fix(.zshrc): change -z to -f for brew check`
- Good: `fix(.zshrc): ensure Homebrew is detected on macOS`
- Keep the subject line under 72 characters.
- Use imperative mood ("add", "fix", "ensure", not "added", "fixes", "ensures").

### Workflow

1. Run `git status` and `git diff` to understand current changes.
2. Identify the smallest atomic unit of change to commit.
3. Run relevant tests/validation for that change.
4. Present the user with:
   - Files to be staged
   - The proposed commit message
   - A brief note on what was validated
5. Wait for the user to approve, modify, or reject.
6. Stage only the approved files and create the commit.
7. If more changes remain, repeat from step 2.
