# Extracting a command from an agent doc

`plugins/building/lib/repo-cmd.sh` answers one question for
the guardrail hooks: which command does this repo use to run its tests, or its
linter? The answer comes from a labelled line in the repo's `AGENTS.md`, with
`CLAUDE.md` as the fallback:

```markdown
- **Test:** `make test-unit`
```

## Problem

A label is not enough on its own. Agent docs are prose, and a line that opens with
a recognised label often continues into a sentence that is describing the command
rather than naming it.

The real case this was written for: `netboxlabs/netbox-changes` documents its CI
job under `- **tests**:` and mentions NetBox's `main` branch before it ever names
the command it runs. A parser that lifts the first inline-code span out of that
line extracts `main`.

## The constraint

The extracted string is handed to a gate that blocks pushes. `main` is not a
program, so it exits non-zero, and the push gate reads that exit code as "your
tests are broken". Every push from that repo is then blocked, for no reason other
than the shape of a sentence in its documentation.

The failure is therefore asymmetric. Extracting nothing is safe, because every
caller fails open and the check is skipped. Extracting the *wrong* string is not
safe, because it turns into a false failure that blocks work.

## The rule

The remainder of the line after the label must be **exactly one inline-code span**
and nothing else. A label line that runs on into prose is a description, not a
command, and is skipped.

Matching is case-insensitive, the first match wins, and the pattern stays within
BSD grep so it works on macOS without GNU coreutils.

## Which version of the doc

test-gate and lint-warn `eval` the command, and Claude Code runs hooks outside its
sandbox. So in a sandboxed session, an agent that edited the doc could have its next
commit or push run any command unsandboxed (#83). The command is therefore read from
the doc as committed at `HEAD`, through `git cat-file`, never from the working tree. An
edit takes effect once committed, and a doc never committed names no command, so the
gate is skipped as for a repo without one. Every `AGENTS.md` and `CLAUDE.md` in the
author's checkouts was committed when this was written.

This closes the one-step route only. It is not a boundary, because a sandboxed agent can
still:

- commit the doc, as the sandbox protects only `hooks` and `config` inside `.git`;
- point `git -C` at a repo it made itself, which the hooks judge since #75;
- edit what the command runs, such as a `Makefile` or the test suite.

Closing those needs a signal that the session is sandboxed, which Claude Code does not
document, or running the command inside a sandbox.

Rejected: checking `git diff --quiet HEAD -- AGENTS.md CLAUDE.md` and then reading the
working tree. It skips the gate whenever the doc has uncommitted changes, runs an
untracked doc whatever it says, and the file can change between the check and the read.

## If you change this

Loosening the rule to "take the first code span" reintroduces the blocked-push
failure above. If a repo's command genuinely cannot be written as a bare labelled
span, fix the agent doc rather than the parser — the doc is the interface, and it
is read by humans too.

`test_repo_cmd.sh` covers the run-on-prose case directly.
