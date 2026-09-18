# Extracting a command from an agent doc

`.claude/marketplace/plugins/guardrails/lib/repo-cmd.sh` answers one question for
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

## If you change this

Loosening the rule to "take the first code span" reintroduces the blocked-push
failure above. If a repo's command genuinely cannot be written as a bare labelled
span, fix the agent doc rather than the parser — the doc is the interface, and it
is read by humans too.

`test_repo_cmd.sh` covers the run-on-prose case directly.
