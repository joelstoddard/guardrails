---
name: draft-pr
description: Create a draft pull request with a standardized What/Why/How body and conventional-commit title. Follow this skill whenever opening a pull request — the draft PR is the human review checkpoint, so the body format is fixed, the title is conventional-commit, and the PR is always marked draft. Main agents only; sub-agents return their work to the main agent to PR.
disable-model-invocation: true
allowed-tools: Bash(git *), Bash(gh pr *), Bash(gh auth *), Bash(gh repo *), Bash(gh api *)
---

## Current state

- Branch: !`git branch --show-current`
- Status: !`git status --short`
- Default branch: !`gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || echo main`
- Commits ahead: !`git log --oneline $(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || echo main)..HEAD 2>/dev/null || echo "(cannot compute — base ref missing)"`
- Existing PR: !`gh pr list --head "$(git branch --show-current)" --state open --json number,url,isDraft 2>/dev/null`
- gh auth: !`gh auth status 2>&1 | head -1`

## Rules

### Always draft
Every PR this skill creates is `--draft`. Never omit the flag, never mark a PR ready for review. The draft state is the human checkpoint — the user transitions the PR to ready-for-review themselves.

### Never push force, never bypass hooks
No `--force`, no `--force-with-lease`, no `--no-verify`. If a push is rejected or a hook fails, surface the error and stop.

### Never create a second PR on a branch
If an open PR already exists for the current branch, surface its URL and stop. Do not create a duplicate. Updating an existing PR is out of scope for this skill.

### Main-agent only
Sub-agents do not create PRs. PR creation IS the human review checkpoint — if a sub-agent is creating a PR, the checkpoint is being skipped. Sub-agents return their work to the calling agent, which creates the PR.

### Title format

Conventional Commits v1.0.0, same rules as the `commit` skill:

```
<type>[optional scope][optional !]: <description>
```

**Types:** `feat`, `fix`, `refactor`, `chore`, `docs`, `style`, `test`, `build`, `ci`, `perf`

**Scope:** Single atomic identifier — never comma-separated.

**Subject:** Imperative mood, under 72 characters, captures the *why*.

Derivation priority:
1. If exactly one commit is ahead of the base, use that commit's subject verbatim.
2. Otherwise, synthesize a single `type(scope): subject` line that summarizes the branch, drawing on the commit subjects and the branch name.

### Body format (non-negotiable)

Exactly three sections, in this order, with these headings:

```markdown
## What
<bulleted summary of the changes — derived from the commits on this branch>

## Why
<motivation — the problem this is solving, drawn from conversation context>

## How
<approach — key design decisions or tradeoffs worth surfacing to the reviewer>
```

- **What** is derivable from `git log <base>..HEAD` alone. No conversation required.
- **Why** and **How** come from conversation context. If conversation context is missing (e.g., the user starts a fresh session and says "PR this branch"), ask the user for the Why and How before proceeding. Never fabricate.

## Workflow

### 1. Preflight — all must pass

Stop and report if any check fails:

- In a git repo (`git rev-parse --git-dir`).
- Current branch is **not** the default branch. Detect default via `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`, fall back to `main`.
- Working tree is clean (`git status --porcelain` empty). If dirty, point the user to the `commit` skill.
- At least one commit ahead of the base. Prefer `origin/<default>` when that ref exists, otherwise local `<default>`. Check with `git rev-list --count <base>..HEAD`.
- `gh` CLI is authenticated (`gh auth status` succeeds).
- No open PR already exists for this branch (`gh pr list --head "$(git branch --show-current)" --state open --json number` returns `[]`).

### 2. Gather content

- **Title:** Conventional Commit format, derived per the rule above.
- **Body:**
  - `## What` from `git log <base>..HEAD --format='%s%n%b'` — bullet the distinct changes.
  - `## Why` from conversation context.
  - `## How` from conversation context.

If Why or How cannot be derived from conversation, ask the user. Do not fabricate.

### 3. Present for approval

Show the user:

- Proposed title.
- Proposed body (rendered).
- Base branch (the detected default).
- Draft status: `true` (always).
- Push plan: whether `git push -u origin <branch>` will create the remote branch or update an existing one.

Wait for explicit approval. If the user requests changes, revise and re-present. Do not create the PR until approved.

### 4. Execute

In order:

1. `git push -u origin "$(git branch --show-current)"` — sets upstream if unset, no force.
2. `gh pr create --draft --base <default-branch> --title <title> --body <body>`.
3. Return the PR URL as the final output.

If step 1 fails, stop — do not attempt step 2.

## Body template

```markdown
## What
- <change 1 — from commit subjects>
- <change 2>

## Why
<motivation from conversation context>

## How
<approach / key decisions from conversation context>
```

## Failure modes

| Condition | Behavior |
|---|---|
| On the default branch | Refuse. Ask user to create a feature branch. |
| Dirty working tree | Refuse. Point to the `commit` skill. |
| No commits ahead of base | Refuse. Nothing to PR. |
| Open PR already exists for branch | Refuse. Surface the existing PR URL. |
| `gh` not authenticated | Refuse. Tell user to run `gh auth login`. |
| Missing Why/How context | Ask the user. Do not fabricate. |
| User rejects title or body | Revise and re-present. Do not create PR until approved. |
| `git push` fails | Surface the error. Do not attempt `gh pr create`. |

## Red flags — stop and re-check

- About to run `gh pr create` without `--draft`.
- About to run `gh pr create` before the user has approved the body.
- About to force-push or use `--no-verify`.
- About to create a second PR when one already exists.
- About to invent a "Why" or "How" because conversation context is thin.

All of these mean: stop, surface the issue to the user, and wait.
