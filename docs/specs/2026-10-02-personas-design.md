# Personas: global specialist subagents, split into rules, skills and hooks

## Problem

A first draft of seven specialist personas (architect, data-engineer, qa-engineer,
release-engineer, sre, security-engineer, technical-writer) arrived as a project-level
bundle: a `CLAUDE.md` that `@import`s an 18 KB `AGENTS.md` of core principles, and one
agent file per persona. The content is good. Its shape is not:

- Everything is prose an agent must remember to apply. Much of it is better enforced by
  a machine (hooks, permissions) or loaded only when relevant (path-scoped rules).
- It is project-scoped, but the personas should be reachable from every repo.
- Document conventions (RFC, ADR, incident write-up) differ between work and personal
  projects, and the draft has one variant.
- Several rules contradict the existing user-global guidance (`.claude/CLAUDE.md`
  "Simplicity First", ponytail): DIP/OCP everywhere, wrap every third-party library,
  inject every side effect, mutation testing on every change.
- It references a "mistakes skill" that does not exist, and a `personas/` path that
  does not match where agents live.
- Findings reported "outside scope" end up only in chat and are never tracked.

The draft's conspicuous formatting (ALWAYS / NEVER / IF / AND / BEFORE, tier tags) is
kept throughout.

## Decisions

| Decision                         | Choice                                                                                                        | Why                                                                                                                             |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| Where personas live              | `~/.claude/agents/`, from this repo's `.claude/agents/`                                                       | User scope reaches every repo. A plugin would namespace them and drop `hooks:` / `permissionMode:` frontmatter                  |
| Split mechanism                  | Rules for file-type domains, agents for judgment, skills for documents, hooks and permissions for enforcement | Each rule goes to the cheapest mechanism that applies it reliably                                                               |
| Conflicts with existing guidance | Simplicity wins                                                                                               | Rewrite the conflicting rules to fire only at a real seam                                                                       |
| Delegation                       | Substantial domain work only                                                                                  | "ALWAYS delegate" globally sends every README tweak through a subagent round-trip; small edits get the path-scoped rules anyway |
| Work variants                    | A private work plugin, not this repo                                                                          | This repo is public (see `docs/design/claude-settings-split.md`); employer process stays in employer-owned git                  |
| Work/personal detection          | Under `~/work` = work                                                                                         | The private work plugin already detects work trees this way                                                                     |
| Personal tracker                 | GitHub issues in the repo the finding belongs to                                                              | The personal Notion has no integration; GitHub is the automatable one. `TODO.md` is migrated to issues                          |
| Work tracker                     | The work plugin's ticket skill                                                                                | Work expects every item as a ticket                                                                                             |

## Layout

```
.claude/rules/                     → ~/.claude/rules/
  core.md            always: keywords, precedence, tiers, proportionality, thresholds,
                     conduct, design, implementation, testing charter, security baseline,
                     version control (WHY line), collaboration, personal-context ownership
  delegation.md      always: orchestrator protocol, persona protocol, report format
  testing.md         paths: test files
  gherkin.md         paths: **/*.feature
  migrations.md      paths: migrations, SQL, alembic
  api-contracts.md   paths: *.proto, openapi*/swagger*, *.graphql, asyncapi*
  delivery.md        paths: CI definitions, Terraform/OpenTofu, Helm/k8s, Dockerfile, compose
  docs.md            paths: docs/**, README*, CHANGELOG*
.claude/agents/<persona>.md (7)    → ~/.claude/agents/
.claude/marketplace/plugins/guardrails/
  skills/mistakes/      broadcast for any mistake or incident; the personal post-mortem
  skills/rfc/           personal RFC → docs/specs/YYYY-MM-DD-<topic>-design.md
  skills/adr/           personal ADR → docs/design/<concept>.md
  skills/track-findings/ file each finding in the session's tracker
  hooks/scripts/{persona-report,findings-capture,findings-gate,suppression-warn}.sh
  lib/findings.sh
```

Path globs, matched relative to the project root:

| Rule               | `paths:`                                                                                                                                                                                                                        |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `testing.md`       | `**/test/**`, `**/tests/**`, `**/__tests__/**`, `**/spec/**`, `**/*_test.*`, `**/*.test.*`, `**/*.spec.*`, `**/test_*.py`, `**/conftest.py`                                                                                     |
| `gherkin.md`       | `**/*.feature`                                                                                                                                                                                                                  |
| `migrations.md`    | `**/migrations/**`, `**/migrate/**`, `**/alembic/**`, `**/*.sql`                                                                                                                                                                |
| `api-contracts.md` | `**/*.proto`, `**/openapi*.{yaml,yml,json}`, `**/swagger*.{yaml,yml,json}`, `**/*.graphql`, `**/asyncapi*.{yaml,yml}`                                                                                                           |
| `delivery.md`      | `.github/workflows/**`, `.gitlab-ci.yml`, `Jenkinsfile`, `.circleci/**`, `**/*.tf`, `**/*.tfvars`, `**/*.hcl`, `**/Chart.yaml`, `**/helm/**`, `**/k8s/**`, `**/kustomization.yaml`, `**/Dockerfile*`, `**/*compose*.{yml,yaml}` |
| `docs.md`          | `docs/**`, `**/README*`, `**/CHANGELOG*`                                                                                                                                                                                        |

Installation:

- **Stow (main).** Neither `~/.claude/agents` nor `~/.claude/rules` exists, so stow links
  each whole directory. No `.stow-local-ignore` change. `scripts/verify.py` gains both
  paths in its linked list.
- **Home Manager (PR #85, unmerged).** It needs two `mkOutOfStoreSymlink` lines in
  `home/claude.nix`, one per directory. They belong on that branch, so PR 3 lists them
  in its description rather than adding a cross-branch dependency.
- **Double load in this repo.** Here `.claude/rules/` and `.claude/agents/` are also
  project scope. Live check 3 confirms whether Claude Code dedupes by real path, as it
  appears to for `.claude/CLAUDE.md`.
- guardrails bumps to `0.11.0`, in `plugin.json` and the marketplace `metadata.version`.

Platform behaviour this relies on (code.claude.com/docs/en/memory and /sub-agents):

- **Same-name agents.** The project copy wins over `~/.claude/agents/`, so a repo can
  shadow a persona.
- **Rules merge.** User and project rules merge, and "Claude may follow either one" on
  conflict. A project rule that contradicts `core.md` is ambiguous, not an override.
- **Broken frontmatter.** It is ignored silently and the rule loads unscoped.
  `test_personas.py` guards this.
- **Symlinks.** User-scope files are trusted, so symlinked `~/.claude/rules/` and
  `~/.claude/agents/` load in the CLI. Cowork desktop sessions skip a symlinked
  `~/.claude/rules/` or `~/.claude/CLAUDE.md`.
- **First creation.** A running session does not see a newly created `~/.claude/agents/`
  until restart.

The zip's `CLAUDE.md` and `AGENTS.md` are not carried as files. Their content is spread
across the rules above.

## Content mapping

| Source                                                              | Destination                             | Change                                                                                                                            |
| ------------------------------------------------------------------- | --------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| AGENTS.md: How to read                                              | `core.md`                               | Kept                                                                                                                              |
| AGENTS.md: Agent Conduct                                            | `core.md`; Delegation → `delegation.md` | Kept                                                                                                                              |
| AGENTS.md: Design, Implementation                                   | `core.md`                               | Simplicity rewrites below                                                                                                         |
| AGENTS.md: Testing charter, gates, TDD, static-analysis suppression | `core.md`                               | They fire on source edits, so they cannot be test-path scoped. Gates become "every gate the project HAS configured"               |
| AGENTS.md: Unit, Regression, Mutation, Coverage, Test hygiene       | `testing.md`                            | Mutation and coverage become the project's configured floor. Missing tooling is a finding, NOT something to add unasked           |
| AGENTS.md: Shift left                                               | `core.md`                               | Local lint/test-before-push is dropped; the guardrails test gate enforces it                                                      |
| AGENTS.md: Security baseline                                        | `core.md`                               | Path reference fixed to the `security-engineer` agent                                                                             |
| AGENTS.md: Version Control                                          | `core.md`                               | Cut to "commit messages explain WHY" and "NEVER commit secrets, generated artefacts, OR large binaries"; nothing else enforces the latter. The commit skill, deny list and default-branch guard enforce the rest |
| AGENTS.md: Collaboration                                            | `core.md`                               | Kept, plus the personal-context ownership line. PR descriptions go through `guardrails:draft-pr`, replacing "the user opens AND sends them" |
| AGENTS.md: Personas table                                           | removed                                 | Agent `description` fields already drive selection                                                                                |
| zip CLAUDE.md: Orchestrator, Persona subagent                       | `delegation.md`                         | Delegation for substantial work. "Read the persona file IN FULL" applies only WHEN no path-scoped rule loaded for that domain     |
| architect: Contract, Behaviour                                      | `api-contracts.md`                      | Rest stays in the agent                                                                                                           |
| data-engineer: Schema change, Migration testing                     | `migrations.md`                         | Rest stays                                                                                                                        |
| qa-engineer: Gherkin                                                | `gherkin.md`                            | Rest stays                                                                                                                        |
| release-engineer: CI/CD, IaC, Twelve Factor                         | `delivery.md`                           | Fix Forward and Cost stay                                                                                                         |
| technical-writer: Principles                                        | `docs.md`                               | Decision documents → `rfc` / `adr` / `mistakes` skills; operational documents stay                                                |
| sre                                                                 | stays                                   | Broadcast → `guardrails:mistakes`. Full post-mortem → the `post-mortem` skill the session context names; none in personal context |

Simplicity rewrites:

- DIP → "Inject a dependency ONLY WHEN a test OR a second implementation needs the seam."
- OCP → dropped.
- ISP → "WHEN you define an interface, keep it small."
- "Inject clock, randomness, network, filesystem, environment" → "ALWAYS keep side effects
  at the edges. Inject them ONLY WHEN a test must control them."
- security-engineer "wrap third-party libraries behind your own interface" → "ALWAYS keep
  third-party calls at the edges. Wrap ONLY WHEN a test OR a second implementation needs it."
- "IF a constraint does not exist, ALWAYS add it BEFORE changing behaviour" → "ALWAYS leave
  the ONE smallest check that fails if the logic breaks. Propose larger gates as findings."
- TDD → applies to non-trivial logic (a branch, a loop, a parser, a money OR security path).
  Trivial one-liners need no test.

Personal-context ownership (`core.md`): "Outside `~/work`, the user owns every service,
alert, API and debt item. Do NOT ask who owns it." Without it every "IF the owner is
unknown, ask" rule fires in every personal repo.

Every agent:

- Its header points at `core.md` and `delegation.md`.
- Its `tools:` gains `Skill`, so it can use the document skills.
- It keeps "IF you cannot see the core principles, STOP AND return BLOCKED" as a tripwire.
- It reads its domain rule file IN FULL before starting. Otherwise a persona that never
  reads a matching file never sees the rules that moved out of it.

## Skills

**`mistakes`.** A broadcast with three headings, used for incidents and for Claude's own
mistakes (a bad push, a deleted file, a false "done"):

1. **What happened**: impact and timeline, facts separated from suspicions.
2. **How it has been fixed**: the change, and the evidence it worked (regression test,
   command, result).
3. **How we will prevent it**: MUST name a deterministic constraint (test, hook, rule,
   gate, permission). "Be more careful" fails the skill.

It names the audience and hands the draft over. It never sends it. Lessons route to
`guardrails:project-memory` (repo) or `guardrails:self-improvement` (skill).

**`rfc` / `adr`.** Personal variants that write to the repo's existing conventions:
`docs/specs/YYYY-MM-DD-<topic>-design.md` and `docs/design/<concept>.md`. A personal ADR
is updated in place AND the stale version deleted, per the user's convention. Work ADRs
are superseded, NEVER edited.

**`track-findings`.** For each finding:

1. Search the tracker for an existing open match, so repeats don't duplicate.
2. File it with label `finding`: `file:line`, evidence, suggested fix, and the branch or
   PR where it was noticed.
3. End the body with the `🤖 Generated with [Claude Code](https://claude.com/claude-code)`
   footer.

It uses the tracker the session context names, or GitHub issues by default. It files in
the repo the finding belongs to. IF the user cannot write to that repo, it asks which
repo to use.

In a repo the user owns personally (`isInOrganization` false AND admin), it files at the
permission prompt. Anywhere else, including every work tracker, it asks in chat first AND
marks the finding `(asked)` until the user answers. The user decided this on 2026-10-02,
because other developers may not want AI-filed issues.

No skill may use `$(` anywhere in its file; the guardrails preamble test enforces this,
because a worktree-isolated session refuses command substitution.

## Tracking findings

Rule (`core.md`): "NEVER leave a finding only in chat. BEFORE ending your turn, ALWAYS
file every finding outside scope with `guardrails:track-findings`, mark it `(asked)` while
the user decides, OR mark it `(declined)` WHEN the user says no." Findings appear under a
heading containing "Findings outside scope", one list item each, each line ending with its
reference.

`findings-capture` and `findings-gate` (below) enforce it deterministically.

## Hooks

| Script                | Event, matcher                                                                                                      | Behaviour                                                                                                                                                    | Failure mode                                                                             |
| --------------------- | ------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------- |
| `persona-report.sh`   | `SubagentStop`, `architect\|data-engineer\|qa-engineer\|release-engineer\|sre\|security-engineer\|technical-writer` | Blocks a final message lacking `## Result: DONE\|PARTIAL\|BLOCKED` or any of the six `###` headings; the reason carries the format                           | Allows when `stop_hook_active`. Fail-open without `jq`                                   |
| `findings-capture.sh` | `SubagentStop`, all agents                                                                                          | Appends the report's findings to a per-session pending file that `findings-gate` surfaces at the next `Stop`                                                 | A background subagent's report never reaches a main-session hook (live check 5). Unsafe session ids are ignored |
| `findings-gate.sh`    | `Stop`                                                                                                              | Blocks once if any item in a findings section of the final message does not end with an issue URL, `#N`, `owner/repo#N`, `(asked)` or `(declined)`, AND lists pending subagent findings, consuming them | Allows when `stop_hook_active`. `ponytail:` ceiling: findings under another heading pass |
| `suppression-warn.sh` | `PostToolUse`, `Edit\|Write\|MultiEdit`                                                                             | Warns, never blocks, on added `it\|test\|describe\|context\|suite.skip(`, `xit(`, `@pytest.mark.skip`, `t.Skip(`, `# noqa`, `eslint-disable`, `@ts-ignore`, `type: ignore`, `as any`, `nolint` | Same shape as `comment-warn.sh`; markdown ignored                                        |

The findings scripts share `lib/findings.sh`, which extracts the items of a findings
section and names the per-session pending file.

## Work layer

The private work plugin provides, behind the same names:

- `rfc`, `adr` and `post-mortem` skills. Each fetches the org's template at invocation
  and drafts to it, with a snapshot of the template's headings as fallback. The main
  session fetches; a persona without connector tools gets the template in its brief.
  Drafts only.
- A `SessionStart` + `SubagentStart` hook that, under `~/work`, adds context:
  - document skills are the work plugin's;
  - the findings tracker is its ticket skill;
  - ownership is the team's (ask).

The public layer never names the work plugin. It reads whatever the session context says.

## Permissions

- `Bash(gh issue create:*)` moves from deny to ask. It is the one creation verb that
  tracking needs; comments, edits and closes stay denied.
- Ask is added for `terraform apply`, `tofu apply`, `kubectl apply`, `kubectl delete`,
  `helm install`, `helm upgrade`, `helm uninstall`, `pulumi up` and `git tag`. These are
  the deterministic form of the personas' "NEVER apply / deploy / tag without approval".
- The gitignored `autoMode.hard_deny` prose gains a matching carve-out. It covers only repos
  the user owns personally, AND requires asking in chat first anywhere else. This is a local
  edit, never committed.

## Verification

Tests follow each repo's existing conventions and run through its documented test
command:

- **Plugin hooks.** Shell tests beside the existing ones: `tests/test_*.sh` using
  `helper.sh`.
  - `test_persona_report.sh`: valid report passes; missing `## Result`, missing heading
    and bad status are blocked; `stop_hook_active` passes.
  - `test_findings.sh`: the parser handles bullets, numbered items, "None" and fenced
    examples. An end-of-line `#12`, issue URL, `(asked)` and `(declined)` count as tracked;
    a mid-line `#85` does not.
  - `test_findings_hooks.sh`: the gate blocks an untracked item once. Capture keeps a
    subagent's findings per session, and the gate surfaces them once and consumes them.
    An unsafe session id is ignored.
  - `test_suppression_warn.sh`: each pattern warns, markdown is ignored, nothing blocks.
- **Consistency.** `test/unit/test_personas.py` (Python `unittest`, like its neighbours):
  - every `guardrails:` skill named in an agent or rule exists;
  - the `SubagentStop` matcher and the agent files list the same personas;
  - every agent has `name`, `description` and `tools`;
  - every rule's frontmatter parses.

  This is the check that would have caught the draft's dangling references.

- **Work plugin.** Its own `tests/test_work_context.sh`: context under `~/work`, silent
  elsewhere.

Live checks cover what the docs leave undocumented. They use temporary `ln -s` links from
the worktree, removed afterwards, and their results go in the PR:

1. A canary in an unscoped rule and in a path-scoped rule appears inside a persona.
2. A persona with `Skill` in `tools:` can invoke `guardrails:mistakes`.
3. Project-scope and user-scope copies of the same rule load once in this repo.
4. The Agent tool's `PostToolUse` matcher name; `last_assistant_message` on `Stop`;
   `SubagentStart` context reaching a persona.

IF check 1 fails, personas preload the core rules through `skills:` instead. That switch
is the user's call.

Results, 2026-10-02: checks 1–3 pass, and `last_assistant_message` is on both `Stop` and
`SubagentStop`. Check 4 changed the design. The Agent tool's `PostToolUse` response is the
async launch record, not the report, even with `background: false`, so findings are
captured at `SubagentStop` instead. `SubagentStop`'s `session_id` is the parent's. Rules
load once: 24,337 context tokens with no rule, 25,929 with it at project scope, 25,928
with it at both scopes.

## Delivery

A stack of draft PRs:

1. Permissions.
2. guardrails skills and hooks, `0.11.0`.
3. Rules, agents, `verify.py`, `test_personas.py`.
4. `TODO.md` → GitHub issues, one approval each; then remove `TODO.md`, its
   `.stow-local-ignore` entry and the `~/TODO.md` symlink.

The findings gate needs `gh issue create` askable before it can demand issues, and the
rules name skills the plugin adds. That fixes the order.

The work plugin gets local commits; it has no remote.

## Out of scope

- Enforcing the Claude Code footer on everything created on the user's behalf, and
  revisiting which publish routes may move from deny to ask. Deferred deliberately.
- Portability of `AGENTS.md` to non-Claude tools. The content moves into Claude Code
  rules.
