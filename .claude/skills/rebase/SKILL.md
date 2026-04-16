---
name: rebase
description: Use when branch work is complete and ready for PR review or merge to main — compacts atomic development commits into a clean, reviewable history.
allowed-tools: Bash(git *)
---

## Current state

- Branch: !`git branch --show-current`
- Commits ahead of main: !`git log main..HEAD --oneline`
- Status: !`git status --short`

## Rules

### Never rebase published branches
Only rebase if the branch **has not been pushed**, or if you have confirmed with the user that a force-push is acceptable. When in doubt, ask.

### Target: reviewable history
The goal is a commit history that tells the story of the PR — not the story of how you wrote it. A reviewer should be able to read the commits and understand what changed and why, without wading through "wip", "fixup", or "add missing semicolon" commits.

### Squash granularity
Aim for one commit per logical concern. If the PR does two unrelated things, keep two commits. Don't over-squash into a single blob commit just to minimize count.

### Commit messages after squash
Each resulting commit must follow [Conventional Commits v1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) — same rules as the `commit` skill. Rewrite messages to describe *why*, not *what*.

### Preserve the base
Always rebase onto the current `main` (or the PR's target branch) to ensure the branch is up to date before the PR is opened.

## Workflow

1. **Confirm no uncommitted changes** — stash or commit first if needed.
2. **Fetch and rebase onto latest main:**
   ```
   git fetch origin
   git rebase origin/main
   ```
   Resolve any conflicts, then continue.
3. **Compact commits with interactive rebase:**
   ```
   git rebase -i origin/main
   ```
   - `pick` the first commit of each logical concern
   - `squash` or `fixup` everything else into it
   - Rewrite the resulting commit messages to be clean and conventional
4. **Verify the result** — run `git log --oneline origin/main..HEAD` and confirm the history reads clearly.
5. **Report to user:** show the final commit list and confirm before any push.

## Quick Reference

| Goal | Command |
|------|---------|
| See commits to compact | `git log --oneline origin/main..HEAD` |
| Update branch from main | `git rebase origin/main` |
| Interactive compact | `git rebase -i origin/main` |
| Abort if something goes wrong | `git rebase --abort` |
| After resolving conflicts | `git rebase --continue` |

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Rebasing a branch others have checked out | Confirm force-push is OK first |
| Single mega-commit for multi-concern PRs | Keep one commit per logical concern |
| Reusing development-time messages ("wip", "fix tests") | Rewrite every message from scratch |
| Forgetting to rebase onto latest main | Always `git fetch && git rebase origin/main` before opening PR |
| Squashing unrelated changes together | Split into separate commits instead |
