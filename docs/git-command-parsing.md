# Detecting whether a command line runs `git <subcommand>`

`.claude/marketplace/plugins/guardrails/lib/git-cmd.sh` answers one question for
the guardrail hooks: does this shell command line actually *run* `git commit` (or
`push`, or …), and if so, which repository will it act on?

## Problem

The first version of the default-branch guard matched the substring `git commit`
anywhere in the command line. That is wrong in the direction that annoys people: a
benign `gh pr create` whose PR body happened to say "git commit" tripped the guard
and blocked the call. Commit messages, grep patterns and PR bodies all routinely
quote git commands.

## The constraint

These are tripwire hooks, deliberately dumb. They run synchronously on every
`Bash` tool call, so parsing has to be cheap, and a parser that is wrong in the
*blocking* direction is worse than one that is wrong in the permissive direction —
a guard that cries wolf trains you to set `ALLOW_DEFAULT_COMMIT=1` out of habit, at
which point it protects nothing.

## Design

For each chained simple command — split on `&&`, `||`, `;`, `|` and newlines —
`_guardrails_invokes_git`:

1. skips leading `VAR=value` assignments,
2. requires the command word itself to be `git`,
3. skips git's global options before matching the subcommand.

Global options that consume a following separate argument (`-C`, `-c`,
`--git-dir`, `--work-tree`, …) are enumerated in
`_guardrails_git_opt_takes_value`, because skipping them means knowing whether to
advance the index by one token or two.

## Which repository the command acts on

Parsing global options is not optional, because `git -C <path> commit` is a real
commit aimed at a different repo. A guard that ignores `-C` is not merely
bypassable — it is wrong in the other direction too, and that is the case that
actually bites.

Working one-worktree-per-ticket, the shell sits in the primary checkout (usually
on the default branch) while the commit is aimed at a worktree. A hook that
resolves the repo from the payload's `cwd` alone reads the primary checkout's
branch and refuses a commit that was never going to land there.

`_guardrails_git_effective_cwd` exists for this. Both routes to another repo have
to be honoured, and they compose, so segments are walked in order:

| Form | Behaviour |
|---|---|
| `cd <path> && git commit` | The payload `cwd` never changes, so this is the form that bites under worktree-per-ticket. |
| `git -C <path> commit` | Cumulative — each `-C` is relative to the previous one. |

## What was rejected

- **Substring matching.** The original approach; produced the `gh pr create` false
  positive above.
- **A real shell parser.** Correct, but far too much machinery for a tripwire that
  runs on every Bash call, and a new dependency for hooks that deliberately have
  none beyond git and jq.
- **Resolving the repo from the hook's `cwd` alone.** Simpler, but silently wrong
  under both `git -C` and `cd … &&` — precisely the worktree-per-ticket workflow
  these hooks exist to support.

## Known limitation

Tokens are split on whitespace with no quote handling, so
`git -C '/path with spaces' commit` is not parsed correctly. This is consistent
with the tripwire framing: the failure is fail-open, and the guard lets the command
through rather than blocking it wrongly.

## Failure mode if you change this

Tightening the matcher so it blocks more aggressively will start blocking benign
`gh` and `grep` invocations. Keep new matching rules fail-open, and add a
regression case to `tests/test_guard_default_branch.sh` naming the command line
that motivated them.
