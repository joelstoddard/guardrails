---
name: stacked-diffs
description: Use when a branch has grown too large to review in one pass, or when starting work that is known to be large — splits the change into a stack of dependent draft PRs (`main ← PR-1 ← PR-2 ← PR-3`), each small enough to review on its own. Also handles rebasing and merging the stack as reviews progress.
allowed-tools: Bash(git *), Bash(gh pr *), Bash(gh api *), Bash(gh repo *)
---

## Current state

- Branch: !`git branch --show-current`
- Stack base (config): !`git config "branch.$(git branch --show-current).stackBase" 2>/dev/null || echo "(unset)"`
- Default branch: !`gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || echo main`
- Commits on this branch: !`git log --oneline $(git config "branch.$(git branch --show-current).stackBase" 2>/dev/null || gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || echo main)..HEAD 2>/dev/null`
- Existing PR: !`gh pr list --head "$(git branch --show-current)" --state open --json number,url,baseRefName 2>/dev/null`

## When to use

- **Reactive split** — you have a finished branch that is too large to review in one pass. Break its commit history into a stack of PRs.
- **Preemptive stacking** — you are starting work you already know will be large. Ship each logical slice as its own PR on top of the previous one.
- **Maintaining a stack** — a lower PR picked up review feedback and changed, so everything above it must be rebased. Or a lower PR merged, so the next PR's base must be retargeted to main.

If the branch is a normal size and reviewable in one sitting, use `rebase` + `draft-pr` instead. Stacking is overhead; only pay it when the alternative is an unreviewable diff.

## Core concepts

### The stack

A stack is an ordered chain of branches where each is based on the previous:

```
main ← feat/thing-01-schema ← feat/thing-02-api ← feat/thing-03-ui
```

Each branch has exactly one **parent** (the branch it was created from) and exactly one PR targeting that parent. The bottom of the stack targets `main` (or whatever the repo's default branch is).

### Parent tracking via git config

The parent of each stacked branch is stored locally in git config:

```
git config branch.<name>.stackBase <parent-branch>
```

This is the source of truth for:
- **What to rebase onto** — the `rebase` skill reads `stackBase` before falling back to `origin/HEAD`.
- **What base to use for the PR** — `gh pr create --base <stackBase>`.
- **How to walk the stack** — enumerate all branches whose `stackBase` points at a given branch to find its children.

`stackBase` is a plain local git config key. It is not pushed with the branch. If you work on the stack from another machine, set it again there.

### Branch naming

Use a shared prefix plus a zero-padded index so branches sort naturally:

```
feat/<topic>-01-<slice>
feat/<topic>-02-<slice>
```

The prefix and slice names are up to the user — the important part is that they sort in stack order and share a prefix so the stack is easy to identify.

## Rules

### Every stacked PR is a draft
Each PR in the stack is opened with `--draft`, same as the `draft-pr` skill. The draft state is the human checkpoint. The user transitions each PR to ready-for-review themselves.

### Bottom-up merging only
The bottom of the stack merges first. Never merge PR-2 before PR-1 — its diff is defined relative to PR-1's changes, and merging it first would apply PR-1's changes into main by accident.

### Force-push with lease only
When rebasing the stack propagates new commits to already-pushed branches, use `git push --force-with-lease`. Never `--force`. If the lease is rejected, stop and investigate — somebody else may have pushed.

### Never push to main
The skill never pushes to the default branch directly. All merges go through the PR UI.

### No `--no-verify`, no silent force-pushes
Hooks exist for a reason. If a hook fails, surface the error and stop.

## Workflows

### A. Reactive split — break a finished branch into a stack

Use when the current branch has grown too large and needs to be split.

1. **Read the commits.** List what is on the branch:
   ```
   git log --oneline --reverse $(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)..HEAD
   ```
2. **Propose a slicing to the user.** Group the commits into logical slices — one slice per reviewable concern. Present the grouping:
   ```
   Slice 1 (feat/thing-01-schema):    <commit-a>, <commit-b>
   Slice 2 (feat/thing-02-api):       <commit-c>, <commit-d>, <commit-e>
   Slice 3 (feat/thing-03-ui):        <commit-f>
   ```
   Wait for user approval. If the commits are not already grouped logically in history, offer to reorder via interactive rebase first (`git rebase -i <base>`), then re-propose.
3. **Create the stack branches.** For each slice, from bottom to top, create a branch at the last commit of that slice:
   ```
   git branch feat/thing-01-schema <last-commit-of-slice-1>
   git config branch.feat/thing-01-schema.stackBase main

   git branch feat/thing-02-api <last-commit-of-slice-2>
   git config branch.feat/thing-02-api.stackBase feat/thing-01-schema

   git branch feat/thing-03-ui <last-commit-of-slice-3>
   git config branch.feat/thing-03-ui.stackBase feat/thing-02-api
   ```
4. **Push each branch.** From bottom to top:
   ```
   git push -u origin feat/thing-01-schema
   git push -u origin feat/thing-02-api
   git push -u origin feat/thing-03-ui
   ```
5. **Open a draft PR for each.** Each PR targets its `stackBase`:
   ```
   gh pr create --draft --base main                     --head feat/thing-01-schema --title "..." --body "..."
   gh pr create --draft --base feat/thing-01-schema     --head feat/thing-02-api    --title "..." --body "..."
   gh pr create --draft --base feat/thing-02-api        --head feat/thing-03-ui     --title "..." --body "..."
   ```
   Use the `draft-pr` body format (What / Why / How). In the **Why**, note this PR's position in the stack and link the PRs above and below it.
6. **Report the stack** to the user with all three PR URLs.

### B. Preemptive stacking — start the next slice on top

Use when the current branch already has its PR open and you are starting the next slice of work.

1. **Confirm the current branch is clean and pushed.**
2. **Create the next branch on top of the current tip:**
   ```
   git switch -c feat/thing-02-api
   git config branch.feat/thing-02-api.stackBase feat/thing-01-schema
   ```
3. **Do the work, commit, push, and open the PR** with `--base feat/thing-01-schema`. Use `commit` then `draft-pr` as normal; `draft-pr` should pick up the stackBase as the base automatically.

### C. Rebase the stack after a lower PR changes

Use when a lower PR picked up review feedback and its branch head moved. Everything above it must be rebased onto the new tip.

1. **Identify the stack order** starting from the changed branch, walking children via `stackBase`:
   ```
   for b in $(git for-each-ref --format='%(refname:short)' refs/heads/); do
     parent=$(git config "branch.$b.stackBase" 2>/dev/null) || continue
     echo "$b -> $parent"
   done
   ```
2. **Walk up the stack, rebasing each child onto its parent's new tip:**
   ```
   git switch feat/thing-02-api
   git rebase feat/thing-01-schema
   git push --force-with-lease origin feat/thing-02-api

   git switch feat/thing-03-ui
   git rebase feat/thing-02-api
   git push --force-with-lease origin feat/thing-03-ui
   ```
   Resolve any conflicts as they occur. If `--force-with-lease` is rejected, stop and investigate.
3. **Report** to the user which branches were rebased and pushed.

### D. Merge the stack — bottom-up

Use after a PR in the stack merges to `main` (or its parent branch). The child PR's base must be retargeted.

1. **Confirm the parent PR merged.** Check via `gh pr view <parent-pr> --json state,mergeCommit`.
2. **Retarget the next PR's base.** The next PR's new base is whatever its old base merged into (usually `main`):
   ```
   gh pr edit <next-pr> --base main
   ```
3. **Update the local `stackBase` config** to match:
   ```
   git config branch.feat/thing-02-api.stackBase main
   ```
4. **Rebase the branch onto the new base** and force-push:
   ```
   git switch feat/thing-02-api
   git fetch origin
   git rebase origin/main
   git push --force-with-lease origin feat/thing-02-api
   ```
5. **Repeat for each higher branch** whose `stackBase` was the just-merged branch — walk up and rebase each in order.

## Quick reference

| Goal | Command |
|------|---------|
| Inspect stack parent | `git config branch.<name>.stackBase` |
| Set stack parent | `git config branch.<name>.stackBase <parent>` |
| See commits on this slice | `git log --oneline $(git config branch.$(git branch --show-current).stackBase)..HEAD` |
| Find children of a branch | `git for-each-ref --format='%(refname:short)' refs/heads/ \| while read b; do [ "$(git config branch.$b.stackBase 2>/dev/null)" = "<parent>" ] && echo "$b"; done` |
| Rebase onto parent's new tip | `git rebase $(git config branch.$(git branch --show-current).stackBase)` |
| Push after rebase | `git push --force-with-lease origin <branch>` |
| Open stacked PR | `gh pr create --draft --base $(git config branch.$(git branch --show-current).stackBase) --title ... --body ...` |
| Retarget PR base after parent merged | `gh pr edit <pr> --base main && git config branch.<name>.stackBase main` |

## Failure modes

| Condition | Behavior |
|---|---|
| User asks to split a branch with unrelated commits jumbled together | Offer to reorder via `git rebase -i <base>` first so slices map to contiguous commit ranges. |
| Current branch has uncommitted changes | Refuse. Point at the `commit` skill. |
| `stackBase` is unset when rebasing | Fall back to `origin/HEAD`, then `main`. Warn the user that stack ordering is not known. |
| `--force-with-lease` rejected | Stop. Someone else (or another machine) pushed. Investigate before overriding. |
| User asks to merge PR-2 before PR-1 | Refuse. Explain bottom-up merge order. |
| Parent PR was squash-merged | The new base is the squash commit on `main`; rebase the child onto `origin/main` (not the old parent ref, which no longer has the same commits). |
| No default branch detectable | Refuse. Ask the user for the default branch. |

## Red flags — stop and re-check

- About to `git push --force` without `--with-lease`.
- About to open a PR that is not `--draft`.
- About to merge a PR whose children have not been retargeted.
- About to split a branch without getting the user's approval of the slicing.
- About to `git branch -D` an old stacked branch before its PR has merged or been closed.
- About to invent a stack when the branch is already small enough to review in one pass.
