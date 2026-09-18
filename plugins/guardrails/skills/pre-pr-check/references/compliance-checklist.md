# Compliance checklist

Language-agnostic categories a healthy project should have. Each entry names
what it is, why it matters, how to gather the evidence, and the exception that
makes "missing" not a gap.

Categories are marked by tier:

- **[diff]** — graded on every pre-PR check, against *this* diff. Asks "did this
  change regress or fail to add it".
- **[project]** — graded only with `--full`. Asks "does the repo have it at all".
  These are near-static between PRs; running them every time produces the same
  list until someone acts on it, which is how a report becomes wallpaper.

Several categories appear in both tiers with different questions. §1 asks
"does this diff add logic without tests" on every check, and "does the project
have a test harness" only under `--full`.

## Severity

- **Missing** — no evidence found, and no exception applies. A gap.
- **Partial** — present but weaker than the target. A gap; name the shortfall,
  not just the category.
- **N/A** — an explicit exception applies. State which one. Not a gap.
- **unknown** — the check could not run. Reported separately from gaps.

## Unknown is never a gap

**A check that could not run is not a check that failed.** A missing tool, an
unreadable file, a `gh` call refused for token scope, a grep that returned
nothing because its own filter was wrong — all of these are **unknown**, and
they are reported in their own section, never folded into either the gaps or
the passes.

Only three things are confirmed negatives: an explicit `false` from a tool that
ran, a count of `0` from a measurement that completed, and an empty list from a
query that succeeded. Everything else is unknown.

Two worked examples, both real, both from building this plugin:

- `grep -rn "claude/worktrees" --include='ignore' . | grep -v worktrees/` —
  the second filter removed the only line that matched, because that line
  contained the search term. The empty result was read as "the repo tracks no
  global ignore file". It tracked one all along. **An empty result is evidence
  about the query first, and about the repo second.**
- `git status --porcelain` returned empty for a worktree holding 986 ignored
  files, because `--porcelain` does not report ignored paths. "Empty output"
  was read as "clean". Deleting on that basis destroyed uncommitted work.
  **Know what your evidence command cannot see.**

When a category's evidence cannot be gathered, say so and say what would be
needed. Never round it toward a verdict in either direction. See the `biases`
skill for the general form of this failure.

## Resolving the base

Every **[diff]** check needs a base to diff against. Resolve it in this order:
the branch's `stackBase` config, the open PR's base, the repo default branch.
Examples below write `origin/main`; substitute the resolved base.

---

## 1. Unit tests

**[diff]** Did this change add or modify logic without adding or modifying a
test? Compare the source files in the diff against the test files in it.

**[project]** Is there a test harness and a documented command to run it?

Evidence: `git diff --name-only origin/main...HEAD`, split into source and
test paths by the repo's own convention. For the project tier, the Test command
in `AGENTS.md`/`CLAUDE.md`, else a test runner in the build manifest.

Exception: a diff that only touches docs, config values, or formatting. A
project that is pure static configuration with no logic.

## 2. Property-based testing

**[diff]** Did this change add parsing, serialization round-trips,
normalization, or algorithmic code with only example-based tests?

**[project]** Is a property-based testing library present at all?

Evidence: the diff's content for parse/encode/decode/normalize surfaces; the
dependency manifest for a PBT library.

Exception: code with no algorithmic surface — glue, wiring, configuration.
Not every function needs a property. This is about the shape of the code
added, not a blanket requirement.

## 3. Mutation testing

**[project]** Is there a mutation testing tool configured?

Line and branch coverage cannot see a vacuous oracle — a test that executes a
path and asserts nothing meaningful passes at high coverage while proving
nothing. Mutation testing is the only mechanical check for that.

Evidence: dependency manifest and CI config for a mutation tool.

Exception: pure glue/config repos. Scope a first pass to the highest-risk
modules rather than the whole tree; a full-repo run is slow and mostly
redundant.

## 4. Coverage gate — aggregate and per-module

**[diff]** Did this change lower a threshold, add an exclusion, or add code
to a module that has its own floor without meeting it?

**[project]** Is there a coverage gate, and does it have a per-module or
per-file floor as well as an aggregate one?

An aggregate threshold can pass while one file sits at 20% because another
sits at 100%. A per-file floor catches that. Most tooling offers only the
aggregate flag, in which case the per-file gate is a script over the coverage
export — and its absence is a **Partial**, not a Missing.

Evidence: the diff for threshold and exclusion changes; CI config and test
config for the gate itself.

Exception: none at the project tier for a repo with logic. A diff that adds no
covered code is N/A at the diff tier.

## 5. Smoke tests

**[project]** Is there a stage that exercises the *built artifact* end to end,
as distinct from unit tests?

"Ran the test suite again" is not a smoke stage. Running the installed binary
from a clean prefix, or launching the built application, is.

Evidence: CI config for a stage that builds then runs. Test paths matching
`*smoke*`.

Exception: a library with no runnable artifact.

**Known failure mode:** a smoke gate that only checks "the process started"
gives false confidence — it can pass while an entire subsystem is broken,
because the gate never exercised it. When reporting this as present, record
what it actually covers, not that one exists.

## 6. Static analysis — lint and format

**[diff]** Did this change add a lint suppression, a warning ignore, or a
formatting exclusion? Each one needs a reason in the diff.

**[project]** Is there a lint command, is it wired into CI, and does it fail
on warnings rather than printing them?

A linter that runs and reports without failing the build is not a gate.

Evidence: the diff for suppression directives; the Lint command in the agent
doc; CI config for a warnings-as-errors flag.

Exception: none for a project with source code. A repo of pure data files is
N/A.

## 7. Static analysis — type checking

**[project]** Is there a type checker, or the nearest enforceable equivalent
for the language, and does it fail the build?

For languages with no bolt-on checker, judge the equivalent rather than the
absence: a compiled language's own strictness settings and warnings-as-errors;
for memory-unsafe languages, a CI job running the test suite under sanitizers,
since no static gate catches use-after-free.

Evidence: the type checker in the dependency manifest and CI; compiler
strictness flags in the build config.

Exception: a dynamically typed codebase where the community norm is untyped —
grade proportionally and recommend a ratchet over one directory, never
"annotate the codebase".

## 8. Editor/agent tooling available

**[project]** Can an agent working in this repo get real diagnostics —
go-to-definition and type errors — rather than inferring structure from grep?

The recurring shape is that the language server is installed while the build
metadata it needs is absent, so it attaches and reports nonsense. Check the
wiring, not the binary: a compilation database for C-family projects, a
project config the server actually reads, and — for pinned toolchains — the
server listed in the toolchain file's components, since it will not be
installed automatically.

Evidence: the language server's config file; the toolchain pin file's
component list; a compilation database.

Exception: a repo small enough to hold in context whole.

## 9. Issue tracking with a priority ladder

**[project]** Are issues enabled, and do milestones form a real ladder rather
than a flat backlog?

Gap conditions in order of severity: issues disabled on a repo with ongoing
development; issues enabled with zero milestones; milestones that exist but
carry no version or theme structure, or a backlog of open issues with no
milestone at all.

Evidence: `gh repo view --json hasIssuesEnabled`, `gh api repos/OWNER/REPO/milestones`,
`gh issue list --search "no:milestone"`.

Exception: a personal repo with no other contributors, where the backlog lives
elsewhere. Say where.

Where release branches exist, the mapping from milestone to branch needs to be
written down **on the branch a contributor would start from**, not only in a
doc on the default branch. The recorded failure mode is a contributor branching
from the default branch because the rule was not visible where they looked.

## 10. Forward-merge automation

**[project]** If release branches exist, is there automation to carry fixes
forward, and are its recent runs passing?

Evidence: release branch refs; a workflow whose name or content mentions
forward-merge or backport; `gh run list` for its recent conclusions.

Exception: **N/A when everything ships off the default branch.** This is the
common case; do not report it as a gap.

Failure modes worth checking by name when the workflow is readable: a default
CI token cannot push changes to workflow files, so a forward-merge that touches
them needs a scoped installation token; an actor filter that excludes bot
authors breaks the cascade for bot-authored commits; and a PR-creation step
that omits an explicit base opens against the repo default regardless of which
branch it forked from.

## 11. CI stages — validation, test, smoke, release gate

**[project]** Are the four stages present as required checks, judged
independently?

- **Validation** — lint, format, type check.
- **Test** — unit and property tests plus the coverage gate.
- **Smoke** — builds and runs the artifact (§5).
- **Release gate** — a check before tag or publish: version bump, changelog
  updated, signing. Distinct from "tests passed"; this is "this specific
  artifact may become a release".

Evidence: CI workflow files and their job names; `gh api` for which checks are
required.

Exception: a private repo may substitute an equivalent local pre-push gate.
**Check whether the repo is public first** — a public repo with no CI is a gap
regardless of local hooks.

**A compatibility claim the build does not exercise is a Partial**, whatever
the language: a manifest promising platforms or versions the matrix never
builds. If the README or manifest promises it, CI should build it.

## 12. CI supply-chain hygiene

**[diff]** Does a workflow file added or changed by this diff reference an
action by mutable tag rather than commit SHA?

**[project]** What fraction of all action references are SHA-pinned, and is
there a workflow scanner?

Report the fraction, not a boolean. A ratio below 100% on an otherwise mature
repo usually means a newer workflow skipped the existing convention rather
than a deliberate choice.

Evidence: `grep -rn "uses:" .github/workflows/` and inspect each reference.

Exception: none. Pinning is maintainable automatically by a dependency bot
configured to pin digests; recommend that alongside fixing current entries, or
the ratio decays with the next added workflow.

## 13. Security scanning as a required check

**[project]** Is there a SAST job, and is it required rather than ad hoc?

A scan run manually and triaged once is weaker than a required job —
regressions between manual runs go uncaught. Record which mode the project is
in.

Evidence: CI config for a scanner job; whether it appears in required checks.

Exception: none for a repo with source code. For memory-unsafe languages a
fuzz target on any parsing surface belongs here, not in the nice-to-have pile.

## 14. Dependency hygiene

**[diff]** Does this diff add a dependency without an exact or bounded pin, or
change a lockfile without the manifest?

**[project]** Is there update automation, are versions pinned, and is there a
cooldown before bumps merge?

Grading at the project tier: no automation is Missing. An onboarding-stub
config with no grouping, automerge, or release-age cooldown is Partial. Two
PR-opening bots configured at once is a gap in itself — they fight over the
same manifests; prefer one for updates and the other for alerts only.
Automation whose automerge cannot fire, because the repo setting is off or
there are no required checks, is Partial — name which prerequisite is missing.

Evidence: the diff for manifest and lockfile changes; the bot config file; the
lockfile and manifest for pin style.

Exception: a repo with no third-party dependencies.

## 15. Changelog

**[diff]** Does this change alter user-facing behaviour without a changelog
entry?

**[project]** Is there a changelog, and does it follow a recognised format
with an unreleased section?

Evidence: a case-insensitive glob for `CHANGELOG*` with any extension. Some
projects split by major version into several files; that is not a missing
changelog.

Exception: a repo with no releases and no consumers. An internal-only change
at the diff tier.

## 16. Docs

**[diff]** Did behaviour change without the corresponding doc changing?

**[project]** Are a readme, a license, an agent doc, and contribution guidance
present?

Evidence: case-insensitive globs without requiring a particular extension —
`LICENCE`, `COPYING`, a licenses directory, and `readme.rst` all count.
**Never report one of these as missing on spelling or extension; confirm with a
directory listing before recommending the file be added.**

An agent doc matters specifically for agentic development — without it every
session re-derives the repo's conventions from scratch.

Exception: contribution guidance is optional for a solo or personal repo. A
repo with no other contributors and no public tracker is a strong signal.

## 17. Local pre-commit or pre-push hooks

**[project]** Is there a local hook that catches problems before they cost a CI
run — or, for a private repo with no CI, that *is* the gate (§11's exception)?

Evidence: a hook config file; the hooks directory; a configured hooks path.

Exception: none, though the bar is low. Do not report a repo as
non-compliant for using an older hook runner; note the faster option exists.

## 18. Branch protection and merge strategy

**[project]** Is the default branch protected, and do required checks include
the CI stages from §11?

Evidence: `gh api repos/OWNER/REPO/branches/BRANCH/protection`. Read the result
carefully:

- Real data returned — grade the required checks and review count. Zero
  required reviews is normal for a solo repo.
- **A 404 from this endpoint specifically means no protection rule exists.**
  That is a confirmed Missing, not unknown.
- Any other failure, almost always insufficient token scope, is **unknown**.
  Never conflate the two.

Exception: a personal repo where the author is the only writer — state it
rather than assuming it.

Some repos deliberately disable squash merging to preserve merge-commit
ancestry, because squashing breaks a later forward-merge's ability to detect
what has already been merged. Where release branches and forward-merge
automation both exist, check the allowed merge methods before recommending
squash as a simplification.

## 19. Container image build hygiene

**Conditional — N/A in one line unless this repo builds an image.** Do not pad
a report with sub-items for a category that does not apply.

**[diff]** Does a Dockerfile added or changed by this diff pin its base by
digest, drop to a non-root user, and declare a healthcheck?

**[project]** The same, across every Dockerfile, plus a Dockerfile linter in
CI and multi-architecture builds where the project claims more than one.

Report the non-root and digest-pinned results as counts over total, not
booleans: three Dockerfiles and one non-root user means two images still run as
root — name which.

Evidence: the diff and a repo-wide glob for Dockerfiles; CI config for a
Dockerfile linter.

Exception: the repo publishes no image.

## 20. Container image supply chain

**Conditional — N/A unless this repo publishes an image.**

**[project]** Are published images signed, do they carry an SBOM and build
provenance, and are they scanned for vulnerabilities as a required check?

Evidence: release and publish workflows for signing, attestation, SBOM
generation, and scanning steps.

Exception: images built only for local development and never published.

## 21. Deployment manifest validation

**Conditional — N/A unless this repo ships deployment manifests or a chart.**

**[diff]** Do manifests or chart templates changed by this diff still render
and validate?

**[project]** Is there a CI job that renders templates and validates the
output against the target schema, and a policy check across every workload?

**Absence of evidence is weak here.** A directory-name search finds manifests
only where it looks; manifests under an unusual directory, or nested deeper
than the search goes, read as absent. **Look at the tree before accepting N/A
on a repo that plainly deploys somewhere.**

Evidence: manifest and chart directories; CI config for a render-and-validate
job.

Exception: manifests that live in a separate deployment repo — grade them
there, and say where. A vendored upstream chart pulled in as a dependency is
upstream code; do not grade it against this project.

---

## Filing gaps

One issue per gap category, never one aggregate compliance issue — they get
triaged, prioritised, and closed independently, and a single giant issue gets
none of that. Do not file for N/A items, and check for an existing open issue
before filing. Follow the repo's own issue conventions for milestone and
labels; use only labels that already exist.
