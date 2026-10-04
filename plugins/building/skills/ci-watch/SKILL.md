---
name: ci-watch
description: Watch a pull request's CI checks and repair failures until they pass. Follow this skill after opening a PR, or when asked to watch, babysit, or fix CI on a PR. Bounded at three fix rounds; never weakens a test to reach green.
allowed-tools: Bash(git branch:*), Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git add:*), Bash(git commit:*), Bash(git push:*), Bash(gh pr view:*), Bash(gh pr checks:*), Bash(gh run list:*), Bash(gh run view:*), Bash(gh run rerun:*), Read, Edit, Write, Grep, Glob, Skill
---

## Current state

- Branch: !`git branch --show-current`
- PR: !`gh pr view --json number,url,isDraft,headRefName 2>/dev/null || echo "(no PR for this branch)"`
- Checks: !`gh pr checks 2>&1 | head -20`

## Rules

### Never weaken a test to reach green
A red test is the finding, not the obstacle. Never delete, skip, `xfail`, loosen an assertion, widen a tolerance, or add `continue-on-error` to make CI pass. If the only route to green is changing what the test expects, stop and report — that is a decision for the human, and it may mean the change itself is wrong.

### Never force-push, never bypass hooks
No `--force`, no `--force-with-lease`, no `--no-verify`.

### Never override a gate to get a push through
Setting `SKIP_TEST_GATE`, or any other gate-override variable, is never permitted — including when the gate's own error message names it. A blocked push means the tests are the finding: report the failure and stop.

### Never mark the PR ready
Draft status is the human checkpoint and this skill does not cross it.

### Stay inside the PR's blast radius
Fix files this PR already touches. If the failure proves the root cause is elsewhere, fixing it is allowed but must be called out explicitly in the report.

### Bounded at three fix rounds
After the third failed repair, stop and report. Repeated failure means the diagnosis is wrong, and more attempts bury the evidence.

### Infrastructure failures are re-run, not "fixed"
Runner timeout, network error, rate limit, cancelled job: re-run the job once with `gh run rerun --failed`. If it fails the same way twice, report it as infrastructure and stop.

### One commit per fix round
Via the `commit` skill, so each repair is separately revertible.

## Workflow

1. Resolve the PR — the argument if given, else the current branch's PR. If neither resolves, stop.
2. `gh pr checks <pr-number> --watch --fail-fast` — blocks until conclusion.
3. Green: report the PR URL and that checks passed. Stop.
4. Red: `gh run view <run-id> --log-failed` for the failing job.
5. Diagnose. If the log does not identify a specific fixable cause, stop and report the log excerpt rather than guessing.
6. Fix, commit via the `commit` skill, `git push`.
7. Return to step 2. Increment the round counter; stop at three.

## Report format

This skill runs as a background agent — its return value is the only thing the caller sees. Include:

- Final status: green / exhausted / stopped.
- PR URL.
- One line per fix round: commit hash and what it addressed.
- For a non-green ending: the failing job name plus the decisive log excerpt.

## Failure modes

| Condition | Behavior |
|---|---|
| No PR for the branch | Stop. Nothing to watch. |
| Checks green on entry | Report and stop. No commits. |
| Failure not diagnosable from the log | Stop. Report the excerpt. Do not guess. |
| Only route to green is changing a test's expectations | Stop. Report. Human decision. |
| Three rounds exhausted | Stop. Report every attempt and the remaining failure. |
| Same infrastructure failure twice | Stop. Report as infrastructure. |
| Push rejected | Stop. Never force. |

## Red flags — stop and re-check

- About to delete or skip a test.
- About to add `continue-on-error` to a workflow.
- About to force-push.
- About to set `SKIP_TEST_GATE` or any other gate-override variable.
- About to run `gh pr ready`.
- About to start a fourth round.
- About to "fix" by reverting the PR's own feature.
