---
name: rebase
description: Use when branch work is complete and ready for PR review or merge — compacts atomic development commits into a clean, reviewable history rebased onto the branch's base (stack parent, repo default branch, or explicit PR base).
allowed-tools: Bash(git *), Bash(gh repo *), Bash(gh pr *)
---

## Current state

- Branch: !`git branch --show-current`
- Stack base (if configured): !`git config --get-regexp '^branch\..*\.stackBase$' 2>/dev/null || echo "(none configured)"`
- PR base: !`gh pr view --json baseRefName -q .baseRefName 2>/dev/null || echo "(no PR for this branch)"`
- Default branch: !`git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main`
- Commits ahead of default: !`git log --oneline origin/HEAD..HEAD 2>/dev/null || echo "(cannot compute — origin/HEAD unset)"`

Resolve the base yourself, in this order: the `stackBase` entry for the branch named
above if one is listed, else the PR base, else the default branch. If that resolved base
is not the default branch, recompute the commit range against it before rebasing.
- Status: !`git status --short`

## Rules

### Never rebase published branches without confirmation
Only rebase if the branch **has not been pushed**, or if you have confirmed with the user that a force-push is acceptable. When force-pushing, always use `--force-with-lease`, never `--force`.

### Target: reviewable history
The goal is a commit history that tells the story of the PR — not the story of how you wrote it. A reviewer should be able to read the commits and understand what changed and why, without wading through "wip", "fixup", or "add missing semicolon" commits.

### Squash granularity
Aim for one commit per logical concern. If the PR does two unrelated things, keep two commits. Don't over-squash into a single blob commit just to minimize count.

### Commit messages after squash
Each resulting commit must follow [Conventional Commits v1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) — same rules as the `commit` skill. Rewrite messages to describe *why*, not *what*.

### Always rebase onto the branch's **base**, not a hardcoded branch
The base is the branch this PR targets — which is not always `main`. Resolve it in this order:

1. **Stack parent:** `git config branch.<name>.stackBase` — set by the `stacked-diffs` skill when this branch is part of a stack.
2. **Open PR's base:** if a PR is already open for this branch, `gh pr view --json baseRefName -q .baseRefName`.
3. **Repo default branch:** `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`, or `git symbolic-ref refs/remotes/origin/HEAD` stripped of the `origin/` prefix.
4. **Fallback:** `main`.

Use the resolved base everywhere the previous version of this skill said `main` or `origin/main`. When fetching, fetch the remote tracking ref `origin/<base>`.

## Workflow

1. **Resolve the base.** Current state above already lists every ingredient. Read them
   in this order and take the first that applies — do not recompute them in shell, as
   the substitution that would require is refused inside a worktree:

   1. **Stack base** — if the listed `branch.<name>.stackBase` entry matches the branch
      named above, its value is the base.
   2. **PR base** — otherwise, if a PR base is shown, use it.
   3. **Default branch** — otherwise use the default branch shown.

   Show the resolved base to the user before proceeding if it is anything other than the repo default — a stack parent is a non-obvious target and worth confirming.

2. **Confirm no uncommitted changes** — stash or commit first if needed.

3. **Fetch and rebase onto the latest base:**
   ```
   git fetch origin
   git rebase "origin/$base"
   ```
   If `$base` is a local stack parent that has not been pushed (or differs from `origin/$base`), rebase onto the local ref instead: `git rebase "$base"`. Resolve any conflicts, then continue.

4. **Compact commits with interactive rebase:**
   ```
   git rebase -i "origin/$base"   # or "$base" for an unpushed stack parent
   ```
   - `pick` the first commit of each logical concern
   - `squash` or `fixup` everything else into it
   - Rewrite the resulting commit messages to be clean and conventional

5. **Verify the result** — run `git log --oneline "origin/$base..HEAD"` and confirm the history reads clearly.

6. **Report to user:** show the final commit list and the resolved base. Confirm before any push. If the branch has been pushed, push with `--force-with-lease`.

## Quick reference

Substitute `$base` with the resolved base branch (stack parent or default).

| Goal | Command |
|------|---------|
| See commits to compact | `git log --oneline "origin/$base..HEAD"` |
| Update branch from base | `git rebase "origin/$base"` |
| Interactive compact | `git rebase -i "origin/$base"` |
| Abort if something goes wrong | `git rebase --abort` |
| After resolving conflicts | `git rebase --continue` |
| Safe force-push after rebase | `git push --force-with-lease origin <branch>` |

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Assuming base is always `main` | Resolve via stackBase → open PR base → repo default. |
| Rebasing a stacked branch onto `main` instead of its parent | Check `git config branch.<name>.stackBase` first. |
| Rebasing a branch others have checked out | Confirm force-push is OK first. |
| Using `--force` instead of `--force-with-lease` | Always use `--force-with-lease` so a concurrent push is detected. |
| Single mega-commit for multi-concern PRs | Keep one commit per logical concern. |
| Reusing development-time messages ("wip", "fix tests") | Rewrite every message from scratch. |
| Forgetting to fetch before rebasing | Always `git fetch origin` before `git rebase "origin/$base"`. |
| Squashing unrelated changes together | Split into separate commits instead. |
