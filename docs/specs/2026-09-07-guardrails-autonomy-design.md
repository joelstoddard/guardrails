# Guardrails autonomy, CI self-healing, and agent memory

Date: 2026-09-07
Status: approved, not yet implemented
Plugin: `.claude/marketplace/plugins/guardrails`, version 0.6.0 → 0.7.0

## Problem

Five gaps in the current guardrails workflow:

1. Opening a draft PR is the end of the agent's involvement. CI failures land
   after the agent has stopped, so the human notices them and hands them back.
2. Merges happen on GitHub (`gh pr merge` is denied), so nothing local knows a
   branch is done. Worktrees accumulate — five exist today, one already merged.
3. `commit` and `draft-pr` both block on explicit approval, which stalls
   otherwise unattended runs even when the session is in auto mode.
4. Agents search recent history rather than the whole population, and reach a
   confident wrong answer from a biased sample.
5. Nothing is learned between sessions. The same wrong first guess about where
   code lives, and the same corrections, recur across sessions and contributors.

## Constraints

- **No `$(` anywhere in a `SKILL.md`.** `tests/test_skill_preambles.sh` fails the
  build on it: a worktree-isolated session refuses any command whose arguments
  come from command substitution, which would abort the skill in the exact
  situation it was written for. Preambles use pipes and `||` only.
- **Hooks fail open.** Every existing hook exits 0 on any unexpected condition.
  New hooks match that. A hook must never be able to block a session.
- **The marketplace is a `directory` source** pointing at
  `/Users/joel/personal/dotfiles/.claude/marketplace`, so skill edits in this
  repo are live for the next session. There is no publish step.
- **Committing on the default branch is blocked** by `guard-default-branch.sh`.
  Anything that writes to a tracked file needs a worktree and a PR.
- **The plugin is global.** Its hooks run in every repo on this machine, so
  every new hook must no-op safely in a repo that knows nothing about it.

## Design

### 1. `ci-watch` — new skill

Watches a PR's checks and repairs failures until green.

`draft-pr` spawns it as a **background agent** after creating the PR, so the
main session is not blocked. It also runs standalone: `/guardrails:ci-watch 42`.

Loop, at most **3 fix rounds**:

```
gh pr checks <pr> --watch --fail-fast
  green → report, stop
  red   → gh run view <run-id> --log-failed
           diagnose → fix → guardrails:commit → git push → re-watch
rounds exhausted, or failure not diagnosable from the log → stop, report
```

Non-negotiable rules, stated in the skill:

- Never weaken, skip, delete, or `xfail` a test to make CI pass. A red test is
  the finding, not the obstacle. If the only way to green is to change the
  test's expectations, stop and report.
- Never `--force`, never `--force-with-lease`, never `--no-verify`.
- Never `gh pr ready`. Draft status stays the human checkpoint.
- Never touch a file outside the diff the PR already owns, unless the failure
  proves the root cause lives elsewhere — and say so in the report.
- Infrastructure failures (runner timeout, network, rate limit) are retried
  once by re-running the job, not "fixed" in code.

Rationale for a subagent over `/loop`: CI runs for minutes, and the token cost
of holding the main session on a polling loop is wasted. The subagent reports
once, terminally.

Permissions already allow this: `gh pr checks`, `gh run view`, `gh run list`,
`git push` are in the user allow list, and the `commit` skill already sanctions
sub-agents committing as they go.

### 2. `post-merge-cleanup.sh` — new SessionStart hook

Deterministic bash. No model involvement, no tokens. It **reports candidates
and never deletes anything.**

```
git fetch --prune origin          # under GIT_TERMINAL_PROMPT=0
for each worktree under .claude/worktrees/:
    branch merged into origin/<default>?
    AND not the directory this session is running in?
      → add a report line naming `git worktree remove <path>`,
        warned if `git status --porcelain --ignored` is non-empty
if main checkout is on <default> and clean:
    git merge --ff-only origin/<default>
```

Why report-only rather than a stricter cleanliness test: `git status
--porcelain` does not list ignored files, and `git worktree remove` does not
refuse on them either. The original "worktree clean" test therefore passed on a
worktree holding 986 ignored paths — including the plan file for this very
change. Making automatic deletion safe would require deciding which local state
is disposable, and that policy call cannot be made once for every repo on the
machine. So the hook surfaces the candidates and the user runs the removal.

Safety rules:

- Nothing is deleted. `git worktree remove` and `git branch -d` are never
  executed by the script.
- A worktree holding uncommitted **or ignored** files is still reported, but its
  line carries a warning to inspect it before removing. A recommended command
  without that warning would relocate the data loss into a command the tool
  endorsed.
- The session's own worktree is never reported.
- Only paths under `.claude/worktrees/` are considered. Worktrees a user placed
  elsewhere are left alone.
- The whole script runs under `timeout` so a slow `git fetch` cannot stall
  session start, and exits 0 on every failure path. `GIT_TERMINAL_PROMPT=0` on
  the fetch so a credential prompt fails fast instead of hanging.

Known limitation: `merge-base --is-ancestor` sees only true merges, so a
squash- or rebase-merged branch is never reported. Under-reporting is the safe
direction for a report — the worktree just stays until the user removes it.

`--ff-only` means a diverged local default branch is left alone, never rewritten.

### 3. `commit` — autonomous

Remove the "present to the user / wait for explicit approval" steps from the
main-agent workflow. It becomes: identify the atomic unit → validate → commit →
report what was committed.

Unchanged: atomicity, conventional-commit format, test-before-commit, and
**never push**. The sub-agent workflow was already autonomous and is untouched.

### 4. `draft-pr` — autonomous, and spawns the watcher

Remove the step-3 approval wait. Add a final step that spawns `ci-watch` as a
background agent against the new PR.

Unchanged: every refusal in the failure-modes table (default branch, dirty tree,
no commits, existing PR, unauthenticated `gh`), and always `--draft`.

Asking the user for a missing Why or How is **retained**. That is not an
approval gate — it is missing information, and the skill's "never fabricate"
rule still binds.

### 5. `biases` — new skill

Targets the failure of searching recent history instead of the whole
population. The core protocol:

1. **Name the population** before searching — "every call site in the repo",
   "every deploy since January", not "recent ones".
2. **Search it whole**, and **report the count** before reading any single hit.
3. Only then sample, and say that you are sampling.

| Bias | How it shows up | Rule |
|---|---|---|
| Recency | `git log -20` when the question is "has this ever happened" | Search the full range, then narrow |
| Selection | Reading the first 3 of 40 grep hits | Count first, then sample deliberately |
| Confirmation | Only searching for what confirms the hypothesis | Search for disconfirming evidence explicitly |
| Availability | First plausible cause becomes the answer | Enumerate at least two candidates before choosing |
| Outcome | Judging a past decision by how it turned out | Judge on what was knowable at the time |
| Survivorship | "Nothing in the logs" read as "it didn't happen" | Ask what would not have been logged |
| Anchoring | The first file read frames the whole investigation | State the frame, then deliberately look outside it |

Includes a red-flags table in the same idiom as the other skills, so the
rationalisation ("the recent ones are representative") is named and refused.

### 6. `self-improvement` — new skill

Standing instruction, model-triggered. There is no "user gave feedback" hook
event, and a regex over prompts produces false positives, so detection is the
model's judgement: the skill's description fires it on a correction, on a
mistake a skill's guidance led to, or on a noticed gap.

**Record (silent, immediate).** Append one JSON object per line to
`~/.claude/skill-lessons.jsonl` — untracked, outside any repo, so recording can
never dirty a working tree or trip the default-branch guard:

```json
{"date":"2026-09-07","skill":"guardrails:commit","trigger":"...","mistake":"...","fix":"...","promoted":false}
```

**Promote (`/guardrails:self-improvement apply`).** Reads the journal, groups
unpromoted entries by skill, and folds them into the `SKILL.md` files through
the normal worktree → commit → draft-PR flow. Skill edits are reviewed like any
other change. Promoted entries are marked `"promoted": true` rather than
deleted, so the history survives.

**Weekly cadence.** A second SessionStart hook, `lessons-nudge.sh`, prints a
one-line count when the journal holds unpromoted entries older than 7 days:

```
3 lessons pending promotion (oldest 9 days). Run /guardrails:self-improvement apply.
```

It only reports. Nothing runs unattended — the apply step opens a PR and edits
the instructions the agent itself follows, which is not something to do while
the human is away.

### 7. `project-memory` — new skill

Two record kinds, one storage convention, because both fire on the same shape of
event and write to the same place:

- **Lesson** — a mistake worth not repeating, by either the user or an agent.
- **Breadcrumb** — where something actually lives, recorded when the first place
  searched turned out to be wrong.

**Storage.** `.claude/docs/lessons/<slug>.md`, one file per lesson, in whatever
repo the session is in. A directory rather than one document so entries stay
independently readable, greppable, and mergeable without conflicts.

```markdown
---
kind: lesson | breadcrumb
date: 2026-09-07
trigger: about to run `stow .` from inside a worktree
---

# Never re-stow from a worktree

**Cost:** overwrote every ~/.config symlink to point at the worktree.
**Do instead:** targeted `ln -s` for the specific files under test.
```

The `trigger` field is the important one: it is what a future agent
pattern-matches against before acting, so it is phrased as the situation, not
the conclusion.

**Breadcrumb protocol.** When a search misses, note the location that was
checked and keep searching. On finding the real location, write a breadcrumb
recording both — the wrong guess is the useful half, because it is what the
next agent will also guess.

**Ignored during trial.** `**/.claude/docs/lessons/` is added to the global
gitignore so the pattern can be exercised locally before it is imposed on
collaborators. Because the global ignore file is currently produced by two
mechanisms on two branches, both are updated:

| Branch | File | Mechanism |
|---|---|---|
| `feat/guardrails-autonomy` | `.config/git/ignore` | stow, current installer |
| `feat/nix-home-manager-flake` (PR #85) | `home/git.nix`, `ignores` list | Home Manager |

The nix branch is where the live `~/.config/git/ignore` symlink currently
resolves, so without the second change the ignore has no effect today; without
the first, it breaks when PR #85 lands. The narrow pattern
(`lessons/`, not all of `.claude/docs/`) keeps future agent docs committable.

Promotion path when the pattern proves out: delete the one ignore line and
commit the directory.

## Files

```
.claude/marketplace/plugins/guardrails/
  .claude-plugin/plugin.json                    0.6.0 → 0.7.0, description
  hooks/hooks.json                              + SessionStart block
  hooks/scripts/post-merge-cleanup.sh           new
  hooks/scripts/lessons-nudge.sh                new
  skills/ci-watch/SKILL.md                      new
  skills/biases/SKILL.md                        new
  skills/self-improvement/SKILL.md              new
  skills/project-memory/SKILL.md                new
  skills/commit/SKILL.md                        autonomous
  skills/draft-pr/SKILL.md                      autonomous, spawns ci-watch
  tests/test_post_merge_cleanup.sh              new
  tests/test_lessons_nudge.sh                   new
.claude-plugin/marketplace.json                 0.6.0 → 0.7.0, description
.config/git/ignore                              + **/.claude/docs/lessons/
```

Plus one commit on `feat/nix-home-manager-flake` adding the same ignore entry to
`home/git.nix`.

## Testing

`tests/test_skill_preambles.sh` covers the four new skills automatically — it
globs `skills/*/SKILL.md` and fails on any `$(`.

`test_post_merge_cleanup.sh` builds throwaway repos with `git init` and asserts
that nothing is deleted and that the report says the right thing:

- a merged, clean worktree survives and **is reported**, with the removal command
- a merged worktree whose only local content is an **ignored** file survives,
  the ignored file survives, and the report line carries the warning — this is
  the regression test for the deletion bug, and it fails if anyone reinstates
  `git worktree remove` or drops the `--ignored` check
- a merged but **dirty** worktree survives and is reported with the warning
- an **unmerged** worktree is not reported at all
- the worktree the session is running in is not reported
- a worktree outside `.claude/worktrees/` is ignored
- a diverged default branch is not rewritten (`--ff-only` refuses)
- a repo not using the `.claude/worktrees` convention is left entirely alone
- a repo with no origin, and a non-git directory, both exit 0

Squash- and rebase-merged branches are deliberately untested because they are
undetectable by `merge-base --is-ancestor` and so out of the hook's scope.
Fixtures assert their own `git worktree add` succeeded, so a broken fixture
fails loudly instead of satisfying the assertions vacuously.

`test_lessons_nudge.sh` asserts: silent on a missing journal, silent on a
journal whose unpromoted entries are all newer than 7 days, reports a count when
they are older, ignores entries already marked promoted, and exits 0 on
malformed JSON.

`ci-watch` has no unit test — it is model behaviour, not a script. Its first
real exercise is the PR that introduces it.

## Rejected alternatives

**`/loop` in the main session for CI watching.** Keeps the session occupied for
the length of a CI run and re-enters the model on every poll, for a task whose
output is a single terminal verdict.

**A `post-merge` skill instead of a hook.** The cleanup is deterministic and
needs no judgement. A skill only runs when something remembers to invoke it,
which is the failure mode that produced five stale worktrees.

**`CronCreate` for the weekly promote.** Session-only, in-memory, and
auto-expires after 7 days — it cannot hold a weekly schedule.

**launchd plist plus systemd timer for the weekly promote.** Two
platform-specific files to maintain, to run a step that opens a PR and rewrites
the agent's own instructions unattended.

**`.git/info/exclude` for the lessons directory.** Per-repo and local, which
avoids the two-branch ignore problem entirely, but requires the skill to write
to `.git/` in every repo it touches and leaves no single place to see or undo
the setting.

**Auto-editing `SKILL.md` on feedback.** Immediate, but dirties the stowed main
checkout of this repo, and edits the instructions the agent is following with no
review. Journal-then-promote keeps the audit trail and the review gate.

**Separate `shared-memory` and `document-first-assumptions` skills.** Same
trigger shape, same storage, same bootstrap logic. One skill with two record
kinds, rather than two skills that must be kept in sync.
