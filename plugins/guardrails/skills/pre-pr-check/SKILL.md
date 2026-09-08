---
name: pre-pr-check
description: Run the repo's documented lint and tests, sweep the diff for secrets, and grade this change against the compliance checklist. Follow this skill before pushing anything to a shared remote or opening a pull request. Pass --full to add the project-level categories that are near-static between PRs.
allowed-tools: Bash, Read, Grep, Glob, Agent
---

## Current state

- Branch: !`git branch --show-current`
- Status: !`git status --short`
- Stack base, if configured: !`git config --get-regexp 'branch\..*\.stackBase' 2>/dev/null || echo "(none)"`
- PR base: !`gh pr view --json baseRefName -q .baseRefName 2>/dev/null || echo "(no PR for this branch)"`
- Default branch: !`gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || echo main`
- Changed files: !`git diff --name-only origin/HEAD...HEAD 2>/dev/null || echo "(cannot resolve origin/HEAD — resolve the base first)"`
- Agent doc: !`ls AGENTS.md CLAUDE.md 2>/dev/null || echo "(neither found at repo root)"`

`allowed-tools` grants unrestricted `Bash` deliberately: the lint and test
commands come from the repo's own agent doc and cannot be enumerated in
advance. Every other grant is the minimum the workflow uses.

## Two tiers

**Gates** block. They are the existing behaviour: lint, tests, and a security
sweep of what this PR would publish.

**Graded categories** are scored against the compliance checklist in
`references/compliance-checklist.md`. Load that file when you reach step 4 —
not before, it is long and most invocations need only part of it.

By default only the checklist's **[diff]** categories run: they ask "did *this
change* regress or fail to add it". With `--full`, the **[project]** categories
run too: they ask "does the repo have it at all". The project tier is excluded
by default because it is near-static between PRs — running it every time
reprints the same list until someone acts on it, which is how a report becomes
wallpaper.

## Rules

### Never stop at the first failure
Run every gate, then grade every applicable category, then report once. A
partial report sends the user round the loop again for something this pass
could already have told them.

### Unknown is never a gap
A check that could not run is **unknown**, reported in its own section. Only an
explicit negative from a tool that ran, a completed count of zero, or an empty
result from a query that succeeded are confirmed negatives. Never round unknown
toward either a pass or a gap. The checklist's preamble carries the reasoning
and two worked examples.

### Never auto-remediate
Report findings; do not fix them in this pass. A secret already in pushed
history needs a rewrite, not a follow-up commit — and silently "fixing" a
finding hides the decision the user should be making.

### State the exception, don't infer it
A category is **N/A** only when a named exception applies. Say which one.
"Probably fine here" is not an exception; that is a gap you have talked
yourself out of.

## Workflow

### 1. Resolve the base

Take the first that applies: the `stackBase` entry matching this branch, the
open PR's base, the repo default branch. Current state above lists all three.
Every diff-scoped check runs against that base.

### 2. Find the commands

Read `AGENTS.md`, falling back to `CLAUDE.md`. `AGENTS.md` wins where a repo
has both. Take the **Test** and **Lint** commands from its Commands section.

If either is undocumented, dispatch one sub-agent to answer "how is this repo
tested and linted?" from the repo's real signals — build manifests, Makefile or
justfile targets, CI workflow jobs. Use its answer for this run, and offer to
record it in the agent doc afterwards, following that doc's existing shape
rather than inventing a format.

An undocumented command is **NOT DOCUMENTED**, which is a finding in its own
right — not a silent skip.

### 3. Run the gates

Run **Lint**, then **Test**, then the security sweep. Continue through
failures.

The security sweep inspects what this PR would actually publish — the diff
against the base and the new commits' contents — for credentials and secrets,
for personal or internal identifiers, and for anything that would be a problem
once the branch is public. Report every hit with its `file:line`.

Before reporting a sweep clean, check whether a hit is already established
practice in the repo: a home path or an author email that an existing tracked
file already carries is not a new disclosure. Say so rather than flagging it
fresh each run.

### 4. Grade the categories

Load `references/compliance-checklist.md` now.

Work the **[diff]** categories. Add the **[project]** categories only if
`--full` was passed. For each, gather the evidence the checklist names, and
assign Missing, Partial, N/A or unknown. A Partial must name its shortfall; an
N/A must name its exception.

Skip conditional categories in one line when their condition does not hold —
a repo that publishes no container image gets one N/A line, not a sub-report.

### 5. Report once

```
| Gate     | Status |
|----------|--------|
| Lint     | PASS / FAIL: n findings / NOT DOCUMENTED |
| Test     | PASS / FAIL: n failures / NOT DOCUMENTED |
| Security | CLEAN / REVIEW: n items |

Graded — this diff:
  §n  <category>   Missing   — <what is absent>
  §n  <category>   Partial   — <the specific shortfall>
  §n  <category>   N/A       — <the exception that applies>

Unknown — could not verify:
  §n  <category>   <why, and what would be needed>

Overall: READY / NOT READY
Gaps: n · Unknown: n · N/A: n
```

**NOT READY** when any gate fails, or any graded category is **Missing**.
Partial and unknown are reported but do not block — a Partial is a real gap
worth a follow-up, and blocking on unknown would punish the user for a missing
token scope.

Under `--full`, report the project tier in its own block so it is visibly not
about this diff.

### 6. Offer to file, do not file

Where gaps merit tracking, offer one issue per gap category — never one
aggregate compliance issue, which gets triaged as a single unit and therefore
not at all. Check for an existing open issue first. Filing is the user's
call: this skill does not create issues.

## Failure modes

| Condition | Behavior |
|---|---|
| No agent doc at repo root | Run the sub-agent discovery, report both commands as NOT DOCUMENTED, offer to write the section. |
| Lint or Test undocumented | NOT DOCUMENTED is a finding. Do not silently skip it. |
| Base cannot be resolved | Stop. Every diff-scoped check depends on it. |
| A tool the checklist names is absent | unknown for that category, naming the tool. Never Missing. |
| `gh` call refused for token scope | unknown. The one exception is a 404 from the branch-protection endpoint, which confirms no rule exists. |
| Secret found in already-pushed history | Report it and say plainly that a new commit will not remove it. |
| Conditional category does not apply | One N/A line. No sub-items. |

## Red flags — stop and re-check

- About to report a category Missing because a command returned nothing, without checking what that command cannot see.
- About to fold an unknown into the gaps, or into the passes, to make the table tidy.
- About to mark a category N/A without naming the exception.
- About to fix a finding instead of reporting it.
- About to run the project tier without `--full`, or skip the diff tier with it.
- About to report before every gate has run.
