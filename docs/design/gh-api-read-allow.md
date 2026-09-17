# Auto-allowing read-only `gh api` calls

Paths below are relative to `.claude/marketplace/plugins/guardrails/` unless they
start with `.claude/` or `docs/`.

## The problem

`Bash(gh api:*)` sits in the `ask` tier of `.claude/user-settings.json`. Permission
rules match a command prefix, and the prefix `gh api` looks the same for a GET and
for a POST, so every `gh api` call prompts. In auto mode that prompt is the one
thing the classifier cannot clear, so a session reading PR review comments stalls
until a human notices.

The deny side already exists: `_guardrails_gh_api_writes` in
`lib/publish-cmd.sh` blocks a `gh api` with a write method or a body flag. What
was missing was the allow side for reads.

## The constraint

A PreToolUse hook that returns `permissionDecision: allow` bypasses every
permission rule for the whole command line, not just the `gh api` part. That
inverts the usual error budget. A deny guard that misses costs a false prompt. An
allow hook that misses runs something unasked, and the prompt was the only gate.

So `hooks/scripts/allow-gh-api-read.sh` fails closed at every step:

- **Allowlist, not denylist.** Only flags known to be read modifiers pass
  (`-X GET`, `-H`, `--jq`, `--paginate`, `--cache`, and the other output flags).
  A flag the script does not know, including a future one gh may add, falls
  through to the ask rule. The denylist in `publish-cmd.sh` is right for a deny
  guard and wrong here.
- **One command only.** The line must be exactly one `gh api` invocation: no
  `|`, `;`, `&&`, `&`, redirect, newline, `$(...)`, backtick, or `$` expansion
  outside single quotes. A pipe to `jq` therefore prompts. `gh api --jq` covers
  that case without a second command.
- **Its own tokenizer.** `lib/shell-split.sh` splits on operators but keeps quote
  characters in the words and treats a backslash as an ordinary character. Both
  are fine for a guard that only needs the first word of each segment. Here they
  are bypasses: `-X 'POST'` would compare unequal to `POST`, and `\'` would open a
  quoted span that bash does not open. The tokenizer in the hook resolves quotes
  and backslashes the way bash does, and rejects anything it cannot resolve.
- **A path, not a URL.** `gh api https://host/x` and `--hostname` can send the
  request, and the token, somewhere other than the configured GitHub host. Only a
  bare endpoint path is accepted.
- **One endpoint.** Two positionals is a gh usage error, and also the shape a
  smuggled word would take.

## Rejected alternatives

- **Permission rules alone.** `Bash(gh api -X GET:*)` matches only that flag
  order, and an allow rule cannot express "unless `-f` appears later".
- **Reusing `_guardrails_gh_api_writes` inverted.** Same denylist, wrong error
  budget; see above.
- **Allowing `gh api ... | jq ...`.** The hook would have to judge `jq` too, and
  the jq program is arbitrary. `--jq` gives the same result under one judgement.
- **A `graphql` exception.** GraphQL reads need `-f query=...`, the same flag that
  carries a mutation. Telling a query from a mutation means parsing GraphQL. It
  stays a prompt.

## Failure mode to watch

The hook and `publish-cmd.sh` both run on every Bash call. If the allowlist here
ever widens to a body flag, `guard-publish.sh` still blocks the write, because a
hook deny wins over a hook allow. If the tokenizer ever accepts an operator or an
expansion, nothing else stands behind it. `tests/test_allow_gh_api_read.sh` pins
each of those shapes; keep a case there for every shape this doc says must prompt.
